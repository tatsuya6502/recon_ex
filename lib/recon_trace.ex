defmodule ReconTrace do
  require :recon_trace

  @moduledoc """
  `ReconTrace` provides functions for tracing events in a safe
  manner for single Erlang virtual machine, currently for function
  calls only. Functionality includes:

  - Nicer to use interface (arguably) than `:dbg` or trace BIFs.
  - Protection against dumb decisions (matching all calls on a node
    being traced, for example)
  - Adding safe guards in terms of absolute trace count or
    rate-limitting
  - Nicer formatting than default traces

  ## Tracing Elixir and Erlang Code

  The Erlang Trace BIFs allow to trace any Elixir and Erlang code at
  all. They work in two parts: pid specifications, and trace patterns.

  Pid specifications let you decide which processes to target. They
  can be specific pids, `all` pids, `existing` pids, or `new` pids
  (those not spawned at the time of the function call).

  The trace patterns represent functions. Functions can be specified
  in two parts: specifying the modules, functions, and arguments, and
  then with Erlang match specifications to add constraints to
  arguments (see `calls/3` for details).

  What defines whether you get traced or not is the intersection of
  both:

      .       _,--------,_      _,--------,_
           ,-'            `-,,-'            `-,
        ,-'              ,-'  '-,              `-,
       |   Matching    -'        '-   Matching    |
       |     Pids     |  Getting   |    Trace     |
       |              |   Traced   |  Patterns    |
       |               -,        ,-               |
        '-,              '-,  ,-'              ,-'
           '-,_          _,-''-,_          _,-'
               '--------'        '--------'

  If either the pid specification excludes a process or a trace
  pattern excludes a given call, no trace will be received.

  ## Example Session

  First let's trace the `:queue.new` functions in any process:

      > ReconTrace.calls({:queue, :new, :_}, 1)
      1
      13:14:34.086078 <0.44.0> :queue.new
      Recon tracer rate limit tripped.

  The limit was set to `1` trace message at most, and `ReconTrace`
  let us know when that limit was reached.

  Let's instead look for all the `:queue.in/2` calls, to see what it
  is we're inserting in queues:

      > ReconTrace.calls({:queue, :in, 2}, 1)
      1
      13:14:55.365157 <0.44.0> :queue.in(a, {[], []})
      Recon tracer rate limit tripped.

  In order to see the content we want, we should change the trace
  patterns to use a `fn` that matches on all arguments in a list
  (`_`) and returns `:return`. This last part will generate a second
  trace for each call that includes the return value:

      > ReconTrace.calls({:queue, :in, fn(_) -> :return end}, 3)
      1

      13:15:27.655132 <0.44.0> :queue.in(:a, {[], []})

      13:15:27.655467 <0.44.0> :queue.in/2 --> {[:a], []}

      13:15:27.757921 <0.44.0> :queue.in(:a, {[], []})
      Recon tracer rate limit tripped.

  Matching on argument lists can be done in a more complex manner:

      > ReconTrace.calls(
      ...>   {:queue, :_,
      ...>    fn([a, _]) when is_list(a); is_integer(a) andalso a > 1 -> :return end}
      ...>   {10, 100}
      ...> )
      32

      13:24:21.324309 <0.38.0> :queue.in(3, {[], []})

      13:24:21.371473 <0.38.0> :queue.in/2 --> {[3], []}

      13:25:14.694865 <0.53.0> :queue.split(4, {[10, 9, 8, 7], [1, 2, 3, 4, 5, 6]})

      13:25:14.695194 <0.53.0> :queue.split/2 --> {{[4, 3, 2], [1]}, {[10, 9, 8, 7],[5, 6]}}

      > ReconTrace.clear
      :ok

  Note that in the pattern above, no specific function (`_`) was
  matched against. Instead, the `fn` used restricted functions to
  those having two arguments, the first of which is either a list or
  an integer greater than `1`.

  The limit was also set using `{10, 100}` instead of an integer,
  making the rate-limitting at 10 messages per 100 milliseconds,
  instead of an absolute value.

  Any tracing can be manually interrupted by calling
  `ReconTrace.clear/0`, or killing the shell process.

  Be aware that extremely broad patterns with lax rate-limitting (or
  very high absolute limits) may impact your node's stability in ways
  `ReconTrace` cannot easily help you with.

  In doubt, start with the most restrictive tracing possible, with low
  limits, and progressively increase your scope.

  See `calls/3` for more details and tracing possibilities.

  ## Structure

  This library is production-safe due to taking the following
  structure for tracing:

  ```
  [IO/Group leader] <---------------------,
    |                                     |
  [shell] ---> [tracer process] ----> [formatter]
  ```

  The tracer process receives trace messages from the node, and
  enforces limits in absolute terms or trace rates, before forwarding
  the messages to the formatter. This is done so the tracer can do as
  little work as possible and never block while building up a large
  mailbox.

  The tracer process is linked to the shell, and the formatter to the
  tracer process. The formatter also traps exits to be able to handle
  all received trace messages until the tracer termination, but will
  then shut down as soon as possible.

  In case the operator is tracing from a remote shell which gets
  disconnected, the links between the shell and the tracer should make
  it so tracing is automatically turned off once you disconnect.

  If sending output to the Group Leader is not desired, you may specify
  a different `pid()` via the option `:io_server` in the `calls/3`
  function. For instance to write the traces to a file you can do
  something like

      > {:ok, dev} = File.open("/tmp/trace", [:write])
      > ReconTrace.calls({:queue, :in, fn(_) -> :return end}, 3,
      >                  [{:io_server, dev}])
      1
      >
      Recon tracer rate limit tripped.
      > File.close(dev).

  The only output still sent to the Group Leader is the rate limit
  being tripped, and any errors. The rest will be sent to the other IO
  server (see http://erlang.org/doc/apps/stdlib/io_protocol.html).
  """

  #############
  ### TYPES ###
  #############

  @type matchspec :: [{[term], [term], [term]}]
  @type shellfun :: (term -> term)
  @type formatterfun :: (tuple -> iodata)
  @type millisecs :: non_neg_integer
  @type pidspec :: :all | :existing | :new | Recon.pid_term()
  @type max_traces :: non_neg_integer
  @type max_rate :: {max_traces, millisecs}

  # trace options
  # default: all
  @type options :: [
          {:pid, pidspec | [pidspec, ...]}
          # default: formatter
          | {:timestamp, :formatter | :trace}
          # default: args
          | {:args, :args | :arity}
          # default: group_leader()
          | {:io_server, pid}
          # default: internal formatter
          | {:formatter, formatterfun}
          # match pattern options
          # default: global
          | {:scope, :global | :local}
        ]

  @type mod :: :_ | module
  @type f :: :_ | atom
  @type args :: :_ | 0..255 | matchspec | shellfun
  @type tspec :: {mod, f, args}
  @type max :: max_traces | max_rate
  @type num_matches :: non_neg_integer

  ##############
  ### Public ###
  ##############

  @doc """
  Stops all tracing at once.
  """
  @spec clear() :: :ok
  def clear() do
    :recon_trace.clear()
  end

  @doc """
  Equivalent to `calls/3`.
  """
  @spec calls(tspec | [tspec, ...], max) :: num_matches
  def calls({_mod, _fun, _args} = tspec, max) do
    :recon_trace.calls(to_erl_tspec(tspec), max, formatter: &format/1)
  end

  def calls(tspecs, max) when is_list(tspecs) do
    Enum.map(tspecs, &to_erl_tspec/1)
    |> :recon_trace.calls(max, formatter: &format/1)
  end

  @doc """
  Allows to set trace patterns and pid specifications to trace
  function calls.

  The basic calls take the trace patterns as tuples of the form
  `{module, function, args}` where:

   - `module` is any Elixir or Erlang module (e.g `Enum` or `:queue`)
   - `function` is any atom representing a function, or the wildcard
      pattern (`:_`)
   - `args` is either the arity of a function (`0`..`255`), a wildcard
      pattern (`:_`),
      a [match specification](http://learnyousomeerlang.com/ets#you-have-been-selected)
      or a function from a shell session that can be transformed into
      a match specification

  There is also an argument specifying either a maximal count (a
  number) of trace messages to be received, or a maximal frequency
  (`{num, millisecs}`).

  Here are examples of things to trace:

  - All calls from the `:queue` module, with 10 calls printed at most:
    `ReconTrace.calls({:queue, :_, :_}, 10)`
  - All calls to `:lists.seq(a, b)`, with 100 calls printed at most:
    `ReconTrace.calls({:lists, :seq, 2}, 100)`
  - All calls to `:lists.seq(a, b)`, with 100 calls per second at most:
    `ReconTrace.calls({:lists, :seq, 2}, {100, 1000})`
  - All calls to `:lists.seq(a, b, 2)` (all sequences increasing by two)
    with 100 calls at most:
    `ReconTrace.calls({:lists, :seq, fn([_, _, 2]) -> :ok end}, 100)`
  - All calls to `:erlang.iolist_to_binary/1` made with a binary as an
    argument already (kind of useless conversion!):
    `ReconTrace.calls({:erlang, :iolist_to_binary, fn([x]) when is_binary(x) -> :ok end}, 10)`
  - Calls to the queue module only in a given process `pid`, at a rate
    of 50 per second at most:
    `ReconTrace.calls({:queue, :_, :_}, {50, 1000}, [pid: pid])`
  - Print the traces with the function arity instead of literal
    arguments:
    `ReconTrace.calls(tspec, max, [args: :arity])`
  - Matching the `filter/2` functions of both `dict` and `lists`
    modules, across new processes only:
    `ReconTrace.calls([{:dict, :filter, 2}, {:lists, :filter, 2}], 10, [pid: :new])`
  - Tracing the `handle_call/3` functions of a given module for all
    new processes, and those of an existing one registered with
    `gproc`:
    `ReconTrace.calls({mod, :handle_call, 3}, {10, 100}, [{:pid, [{:via, :gproc, name}, :new]}`
  - Show the result of a given function call:
    `ReconTrace.calls({mod, fun, fn(_) -> :return end}, max, opts)`
    or
    `ReconTrace.calls({mod, fun, [{:_, [], [{:return_trace}]}]}, max, opts)`,
    the important bit being the `:return` or the `{:return_trace}`
    match spec value.

  There's a few more combination possible, with multiple trace
  patterns per call, and more options:

  - `{:pid, pid_spec}`: which processes to trace. Valid options is any
    of `all`, `new`, `existing`, or a process descriptor (`{a, b, c}`,
    `"<a.b.c>"`, an atom representing a name, `{:global, name}`,
    `{:via, registrar, name}`, or a pid). It's also possible to specify
    more than one by putting them in a list.
  - `{:timestamp, :formatter | :trace}`: by default, the formatter
    process adds timestamps to messages received. If accurate
    timestamps are required, it's possible to force the usage of
    timestamps within trace messages by adding the option
    `{:timestamp, :trace}`.
  - `{:args, :arity | :args}`: whether to print arity in function
    calls or their (by default) literal representation.
  - `{:scope, :global | :local}`: by default, only `global` (fully
    qualified function calls) are traced, not calls made internally.
    To force tracing of local calls, pass in `{:scope, :local}`. This
    is useful whenever you want to track the changes of code in a
    process that isn't called with `module.fun(args)`, but just
    `fun(args)`.
  - `{:formatter, fn(term) -> io_data() end}`: override the default
     formatting functionality provided by ReconTrace.
  - `{:io_server, pid() | atom()}`: by default, recon logs to the
    current group leader, usually the shell. This option allows to
    redirect trace output to a different IO server (such as a file
    handle).

  Also note that putting extremely large `max` values (i.e. `99999999`
  or `{10000, 1}`) will probably negate most of the safe-guarding this
  library does and be dangerous to your node. Similarly, tracing
  extremely large amounts of function calls (all of them, or all of
  `:io` for example) can be risky if more trace messages are generated
  than any process on the node could ever handle, despite the
  precautions taken by this library.
  """
  @spec calls(tspec | [tspec, ...], max, options) :: num_matches
  def calls({_mod, _fun, _args} = tspec, max, opts) do
    :recon_trace.calls(to_erl_tspec(tspec), max, add_formatter(opts))
  end

  def calls(tspecs, max, opts) when is_list(tspecs) do
    Enum.map(tspecs, &to_erl_tspec/1)
    |> :recon_trace.calls(max, add_formatter(opts))
  end

  @doc """
  Returns tspec with its `shellfun` replaced with `matchspec`.
  This futction is used by `calls/2` and `calls/3`.
  """
  @spec to_erl_tspec(tspec) :: tspec
  def to_erl_tspec({mod, fun, shellfun}) when is_function(shellfun) do
    {mod, fun, fun_to_match_spec(shellfun)}
  end

  def to_erl_tspec({_mod, _fun, _arity_or_matchspec} = tspec) do
    tspec
  end

  @doc """
  The default trace formatting functionality provided by ReconTrace.
  This can be overridden by passing
  `{:formatter, fn(term) -> io_data() end}` as an option to `calls/3`.
  """
  @spec format(trace_msg :: tuple) :: iodata
  def format(trace_msg) do
    {type, pid, {hour, min, sec}, trace_info} = extract_info(trace_msg)
    header = :io_lib.format(~c"~n~2.2.0w:~2.2.0w:~9.6.0f ~p", [hour, min, sec, pid])
    body = format_body(type, trace_info) |> String.replace("~", "~~")
    ~c"#{header} #{body}\n"
  end

  ###############
  ### Private ###
  ###############

  defp add_formatter(opts) do
    case :proplists.get_value(:formatter, opts) do
      func when is_function(func, 1) ->
        opts

      _ ->
        [{:formatter, &format/1} | opts]
    end
  end

  defp format_body(:receive, [msg]) do
    "< #{inspect(msg, pretty: true)}"
  end

  defp format_body(:send, [msg, to]) do
    " > #{inspect(to, pretty: true)}: #{inspect(msg, pretty: true)}"
  end

  defp format_body(:send_to_non_existing_process, [msg, to]) do
    " > (non_existent) #{inspect(to, pretty: true)}: #{inspect(msg, pretty: true)}"
  end

  defp format_body(:call, [{m, f, args}]) do
    "#{format_module(m)}.#{f}#{format_args(args)}"
  end

  defp format_body(:return_to, [{m, f, arity}]) do
    "#{format_module(m)}.#{f}/#{arity}"
  end

  defp format_body(:return_from, [{m, f, arity}, return]) do
    "#{format_module(m)}.#{f}/#{arity} --> #{inspect(return, pretty: true)}"
  end

  defp format_body(:exception_from, [{m, f, arity}, {class, val}]) do
    "#{format_module(m)}.#{f}/#{arity} #{class} #{inspect(val, pretty: true)}"
  end

  defp format_body(:spawn, [spawned, {m, f, args}]) do
    "spawned #{inspect(spawned, pretty: true)} as #{format_module(m)}.#{f}#{format_args(args)}"
  end

  defp format_body(:exit, [reason]) do
    "EXIT #{inspect(reason, pretty: true)}"
  end

  defp format_body(:link, [linked]) do
    "link(#{inspect(linked, pretty: true)})"
  end

  defp format_body(:unlink, [linked]) do
    "unlink(#{inspect(linked, pretty: true)})"
  end

  defp format_body(:getting_linked, [linker]) do
    "getting linked by #{inspect(linker, pretty: true)}"
  end

  defp format_body(:getting_unlinked, [unlinker]) do
    "getting unlinked by #{inspect(unlinker, pretty: true)}"
  end

  defp format_body(:register, [name]) do
    "registered as #{inspect(name, pretty: true)}"
  end

  defp format_body(:unregister, [name]) do
    "no longer registered as #{inspect(name, pretty: true)}"
  end

  defp format_body(:in, [{m, f, arity}]) do
    "scheduled in for #{format_module(m)}.#{f}/#{arity}"
  end

  defp format_body(:in, [0]) do
    "scheduled in"
  end

  defp format_body(:out, [{m, f, arity}]) do
    "scheduled out from #{format_module(m)}.#{f}/#{arity}"
  end

  defp format_body(:out, [0]) do
    "scheduled out"
  end

  defp format_body(:gc_start, [info]) do
    "gc beginning -- heap #{calc_total_heap_size(info)} bytes"
  end

  defp format_body(:gc_end, [info]) do
    "gc finished -- heap #{calc_total_heap_size(info)} bytes"
  end

  defp format_body(type, trace_info) do
    "unknown trace type #{inspect(type, pretty: true)} -- #{inspect(trace_info, pretty: true)}"
  end

  defp extract_info(trace_msg) do
    case :erlang.tuple_to_list(trace_msg) do
      [:trace_ts, pid, type | info] ->
        {trace_info, [timestamp]} = :lists.split(:erlang.length(info) - 1, info)
        {type, pid, to_hms(timestamp), trace_info}

      [:trace, pid, type | trace_info] ->
        {type, pid, to_hms(:os.timestamp()), trace_info}
    end
  end

  defp to_hms({_, _, micro} = stamp) do
    {_, {h, m, secs}} = :calendar.now_to_local_time(stamp)
    seconds = rem(secs, 60) + micro / 1_000_000
    {h, m, seconds}
  end

  defp to_hms(_) do
    {0, 0, 0}
  end

  defp format_module(module_atom) do
    to_string(module_atom) |> format_module1
  end

  defp format_module1(<<"Elixir.", module_str::binary>>) do
    module_str
  end

  defp format_module1(module_str) do
    ":" <> module_str
  end

  defp format_args(arity) when is_integer(arity) do
    "/#{arity}"
  end

  defp format_args(args) when is_list(args) do
    arg_str = Enum.map(args, &inspect(&1, pretty: true)) |> Enum.join(", ")
    "(" <> arg_str <> ")"
  end

  defp calc_total_heap_size(info) do
    info[:heap_size] + info[:old_heap_size] + info[:mbuf_size]
  end

  defp fun_to_match_spec(shell_fun) do
    case :erl_eval.fun_data(shell_fun) do
      {:fun_data, import_list, clauses} ->
        case :ms_transform.transform_from_shell(:dbg, clauses, import_list) do
          {:error, [{_, [{_, _, code} | _]} | _], _} ->
            IO.puts("Error: #{:ms_transform.format_error(code)}")
            {:error, :transform_error}

          [{args, gurds, [:return]}] ->
            [{args, gurds, [{:return_trace}]}]

          match_spec ->
            match_spec
        end

      false ->
        exit(:shell_funs_only)
    end
  end
end
