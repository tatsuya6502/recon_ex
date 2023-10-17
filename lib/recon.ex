defmodule Recon do
  require :recon

  @moduledoc """
  `Recon`, as a module, provides access to the high-level
  functionality contained in the ReconEx application.

  It has functions in five main categories:

  1. **State information**
     * Process information is everything that has to do with the
       general state of the node. Functions such as `info/1` and
       `info/3` are wrappers to provide more details than
       `:erlang.process_info/1`, while providing it in a
       production-safe manner. They have equivalents to
       `:erlang.process_info/2` in the functions `info/2` and `info/4`,
       respectively.
     * `proc_count/2` and `proc_window/3` are to be used when you
       require information about processes in a larger sense:
       biggest consumers of given process information (say memory or
       reductions), either absolutely or over a sliding time window,
       respectively.
     * `bin_leak/1` is a function that can be used to try and see if
       your Erlang node is leaking refc binaries. See the function
       itself for more details.
     * Functions to access node statistics, in a manner somewhat
       similar to what [vmstats](https://github.com/ferd/vmstats)
       provides as a library. There are 3 of them:
       `node_stats_print/2`, which displays them, `node_stats_list/2`,
       which returns them in a list, and `node_stats/4`, which
       provides a fold-like interface for stats gathering. For CPU
       usage specifically, see `scheduler_usage/1`.
  2. **OTP tools**
     * This category provides tools to interact with pieces of OTP
       more easily. At this point, the only function included is
       `get_state/1`, which works as a wrapper around `get_state/2`,
       which works as a wrapper around `:sys.get_state/1` in OTP
       R16B01, and provides the required functionality for older
       versions of Erlang.
  3. **Code Handling**
     * Specific functions are in `Recon` for the sole purpose of
       interacting with source and compiled code. `remote_load/1` and
       `remote_load/2` will allow to take a local module, and load it
       remotely (in a diskless manner) on another Erlang node you're
       connected to.
     * `source/1` allows to print the source of a loaded module, in
       case it's not available in the currently running node.
  4. **Ports and Sockets**
     * To make it simpler to debug some network-related issues, recon
       contains functions to deal with Erlang ports (raw, file
       handles, or inet). Functions `tcp/0`, `udp/0`, `sctp/0`,
       `files/0`, and `port_types/0` will list all the Erlang ports of
       a given type. The latter function prints counts of all
       individual types.
     * Port state information can be useful to figure out why certain
       parts of the system misbehave. Functions such as `port_info/1`
       and `port_info/2` are wrappers to provide more similar or more
       details than `:erlang.port_info/1` and `:erlang.port_info/2`,
       and, for inet ports, statistics and options for each socket.
     * Finally, the functions `inet_count/2` and `inet_window/3`
       provide the absolute or sliding window functionality of
       `proc_count/2` and `proc_count/3` to inet ports and connections
       currently on the node.
  5. **RPC**
     * These are wrappers to make RPC work simpler with clusters of
       Erlang nodes. Default RPC mechanisms (from the `:rpc` module)
       make it somewhat painful to call shell-defined funs over node
       boundaries. The functions `rpc/1`, `rpc/2`, and `rpc/3` will do
       it with a simpler interface.
     * Additionally, when you're running diagnostic code on remote
       nodes and want to know which node evaluated what result, using
       `named_rpc/1`, `named_rpc/2`, and `named_rpc/3` will wrap the
       results in a tuple that tells you which node it's coming from,
       making it easier to identify bad nodes.
  """

  #############
  ### TYPES ###
  #############

  @type proc_attrs ::
          {pid, attr :: term,
           [
             name ::
               atom
               | {:current_function, mfa}
               | {:initial_call, mfa},
             ...
           ]}

  @type inet_attr_name :: :recv_cnt | :recv_oct | :send_cnt | :send_oct | :cnt | :oct

  @type inet_attrs :: {port, attr :: term, [{atom, term}]}

  @type pid_term ::
          pid
          | atom
          | charlist
          | {:global, term}
          | {:via, module, term}
          | {non_neg_integer, non_neg_integer, non_neg_integer}

  @type info_type :: :meta | :signals | :location | :memory_used | :work

  @type info_meta_key :: :registered_name | :dictionary | :group_leader | :status
  @type info_signals_key :: :links | :monitors | :monitored_by | :trap_exit
  @type info_location_key :: :initial_call | :current_stacktrace
  @type info_memory_key ::
          :memory | :message_queue_len | :heap_size | :total_heap_size | :garbage_collection
  @type info_work_key :: :reductions

  @type info_key ::
          info_meta_key | info_signals_key | info_location_key | info_memory_key | info_work_key

  @type stats :: {[absolutes :: {atom, term}], [increments :: {atom, term}]}

  @type interval_ms :: pos_integer
  @type time_ms :: pos_integer
  @type timeout_ms :: non_neg_integer | :infinity

  @type port_term :: port | charlist | atom | pos_integer

  @type port_info_type :: :meta | :signals | :io | :memory_used | :specific

  @type port_info_meta_key :: :registered_name | :id | :name | :os_pid
  @type port_info_signals_key :: :connected | :links | :monitors
  @type port_info_io_key :: :input | :output
  @type port_info_memory_key :: :memory | :queue_size
  @type port_info_specific_key :: atom

  @type port_info_key ::
          port_info_meta_key
          | port_info_signals_key
          | port_info_io_key
          | port_info_memory_key
          | port_info_specific_key

  @type nodes :: node | [node, ...]
  @type rpc_result :: {[success :: term], [fail :: term]}

  ##################
  ### PUBLIC API ###
  ##################

  ### Process Info ###

  @doc """
  Equivalent to `info(<a.b.c>)` where `a`, `b`, and `c` are integers
  part of a pid.
  """
  @spec info(non_neg_integer, non_neg_integer, non_neg_integer) ::
          [{info_type, [{info_key, term}]}, ...]
  def info(a, b, c), do: :recon.info(a, b, c)

  @doc """
  Equivalent to `info(<a.b.c>, key)` where `a`, `b`, and `c` are
  integers part of a pid.
  """
  @spec info(non_neg_integer, non_neg_integer, non_neg_integer, key :: info_type | [atom] | atom) ::
          term
  def info(a, b, c, key), do: :recon.info(a, b, c, key)

  @doc """
  Allows to be similar to `:erlang.process_info/1`, but excludes
  fields such as the mailbox, which have a tendency to grow and be
  unsafe when called in production systems. Also includes a few more
  fields than what is usually given (`monitors`, `monitored_by`,
  etc.), and separates the fields in a more readable format based on
  the type of information contained.

  Moreover, it will fetch and read information on local processes that
  were registered locally (an atom), globally (`{:global, name}`), or
  through another registry supported in the `{:via, module, name}`
  syntax (must have a `module.whereis_name/1` function). Pids can also
  be passed in as a string (`"PID#<0.39.0>"`, `"<0.39.0>"`) or a
  triple (`{0, 39, 0}`) and will be converted to be used.
  """
  @spec info(pid_term) :: [{info_type, [{info_key, value :: term}]}, ...]
  def info(pid_term) do
    ReconLib.term_to_pid(pid_term) |> :recon.info()
  end

  @doc """
  Allows to be similar to `:erlang.process_info/2`, but allows to sort
  fields by safe categories and pre-selections, avoiding items such as
  the mailbox, which may have a tendency to grow and be unsafe when
  called in production systems.

  Moreover, it will fetch and read information on local processes that
  were registered locally (an atom), globally (`{:global, name}`), or
  through another registry supported in the `{:via, module, name}`
  syntax (must have a `module.whereis_name/1` function). Pids can also
  be passed in as a string (`"#PID<0.39.0>"`, `"<0.39.0>"`) or a
  triple (`{0, 39, 0}`) and will be converted to be used.

  Although the type signature doesn't show it in generated
  documentation, a list of arguments or individual arguments accepted
  by `:erlang.process_info/2' and return them as that function would.

  A fake attribute `:binary_memory` is also available to return the
  amount of memory used by refc binaries for a process.
  """
  @spec info(pid_term, info_type) :: {info_type, [{info_key, term}]}
  @spec info(pid_term, [atom]) :: [{atom, term}]
  @spec info(pid_term, atom) :: {atom, term}
  def info(pid_term, info_type_or_keys) do
    ReconLib.term_to_pid(pid_term) |> :recon.info(info_type_or_keys)
  end

  @doc """
  Fetches a given attribute from all processes (except the caller) and
  returns the biggest `num` consumers.
  """
  # @todo (Erlang Recon) Implement this function so it only stores
  # `num` entries in memory at any given time, instead of as many as
  # there are processes.
  @spec proc_count(attribute_name :: atom, non_neg_integer) :: [proc_attrs]
  def proc_count(attr_name, num) do
    :recon.proc_count(attr_name, num)
  end

  @doc """
  Fetches a given attribute from all processes (except the caller) and
  returns the biggest entries, over a sliding time window.

  This function is particularly useful when processes on the node are
  mostly short-lived, usually too short to inspect through other
  tools, in order to figure out what kind of processes are eating
  through a lot resources on a given node.

  It is important to see this function as a snapshot over a sliding
  window. A program's timeline during sampling might look like this:

  `  --w---- [Sample1] ---x-------------y----- [Sample2] ---z--->`

  Some processes will live between `w` and die at `x`, some between
  `y` and `z`, and some between `x` and `y`. These samples will not be
  too significant as they're incomplete. If the majority of your
  processes run between a time interval `x`...`y` (in absolute terms),
  you should make sure that your sampling time is smaller than this so
  that for many processes, their lifetime spans the equivalent of `w`
  and `z`. Not doing this can skew the results: long-lived processes,
  that have 10 times the time to accumulate data (say reductions) will
  look like bottlenecks when they're not one.

  **Warning:** this function depends on data gathered at two
  snapshots, and then building a dictionary with entries to
  differentiate them. This can take a heavy toll on memory when you
  have many dozens of thousands of processes.
  """
  @spec proc_window(
          attribute_name :: atom,
          non_neg_integer,
          milliseconds :: pos_integer
        ) :: [proc_attrs]
  def proc_window(attr_name, num, time) do
    :recon.proc_window(attr_name, num, time)
  end

  @doc """
  Refc binaries can be leaking when barely-busy processes route them
  around and do little else, or when extremely busy processes reach a
  stable amount of memory allocated and do the vast majority of their
  work with refc binaries. When this happens, it may take a very long
  while before references get deallocated and refc binaries get to be
  garbage collected, leading to out of memory crashes. This function
  fetches the number of refc binary references in each process of the
  node, garbage collects them, and compares the resulting number of
  references in each of them. The function then returns the `n`
  processes that freed the biggest amount of binaries, potentially
  highlighting leaks.

  See [the Erlang/OTP Efficiency Guide](http://www.erlang.org/doc/efficiency_guide/binaryhandling.html#id65722)
  for more details on refc binaries.
  """
  @spec bin_leak(pos_integer) :: [proc_attrs]
  def bin_leak(n), do: :recon.bin_leak(n)

  @doc """
  Shorthand for `node_stats(n, interval, fn(x, _) -> IO.inspect(x, pretty: true) end, :ok)`
  """
  @spec node_stats_print(repeat :: non_neg_integer, interval_ms) :: term
  def node_stats_print(n, interval) do
    fold_fun = fn x, _ ->
      IO.inspect(x, pretty: true)
      :ok
    end

    node_stats(n, interval, fold_fun, :ok)
  end

  @doc """
  Because Erlang CPU usage as reported from `top` isn't the most
  reliable value (due to schedulers doing idle spinning to avoid going
  to sleep and impacting latency), a metric exists that is based on
  scheduler wall time.

  For any time interval, Scheduler wall time can be used as a measure
  of how **busy** a scheduler is. A scheduler is busy when:

  - executing process code
  - executing driver code
  - executing NIF code
  - executing BIFs
  - garbage collecting
  - doing memory management

  A scheduler isn't busy when doing anything else.
  """
  @spec scheduler_usage(interval_ms) ::
          [{scheduler_id :: pos_integer, usage :: number()}]
  def scheduler_usage(interval) when is_integer(interval) do
    :recon.scheduler_usage(interval)
  end

  @doc """
  Shorthand for `node_stats(n, interval, fn(x, acc) -> [x | acc] end, [])`
  with the results reversed to be in the right temporal order.
  """

  @spec node_stats_list(repeat :: non_neg_integer, interval_ms) :: [stats]
  def node_stats_list(n, interval), do: :recon.node_stats_list(n, interval)

  @doc """
  Gathers statistics `n` time, waiting `interval` milliseconds between
  each run, and accumulates results using a folding function `fold_fun`.
  The function will gather statistics in two forms: Absolutes and
  Increments.

  Absolutes are values that keep changing with time, and are useful to
  know about as a datapoint: process count, size of the run queue,
  error_logger queue length, and the memory of the node (total,
  processes, atoms, binaries, and ets tables).

  Increments are values that are mostly useful when compared to a
  previous one to have an idea what they're doing, because otherwise
  they'd never stop increasing: bytes in and out of the node, number
  of garbage collector runs, words of memory that were garbage
  collected, and the global reductions count for the node.
  """
  @spec node_stats(
          non_neg_integer,
          interval_ms,
          fold_fun :: (stats, acc :: term -> term),
          acc0 :: term
        ) ::
          acc1 :: term
  def node_stats(n, interval, fold_fun, init) do
    :recon.node_stats(n, interval, fold_fun, init)
  end

  ### OTP & Manipulations ###

  @doc """
  Shorthand call to `get_state(pid_term, 5000)`
  """
  @spec get_state(pid_term) :: term
  def get_state(pid_term), do: :recon.get_state(pid_term)

  @doc """
  Fetch the internal state of an OTP process. Calls `:sys.get_state/2`
  directly in OTP R16B01+, and fetches it dynamically on older
  versions of OTP.
  """
  @spec get_state(pid_term, timeout_ms) :: term
  def get_state(pid_term, timeout), do: :recon.get_state(pid_term, timeout)

  ### Code & Stuff ###

  @doc """
  Equivalent `remote_load(nodes(), mod)`.
  """
  @spec remote_load(module) :: term
  def remote_load(mod), do: :recon.remote_load(mod)

  @doc """
  Loads one or more modules remotely, in a diskless manner. Allows to
  share code loaded locally with a remote node that doesn't have it.
  """
  @spec remote_load(nodes, module) :: term
  def remote_load(nodes, mod), do: :recon.remote_load(nodes, mod)

  @doc """
  Obtain the source code of a module compiled with `debug_info`. The
  returned list sadly does not allow to format the types and typed
  records the way they look in the original module, but instead goes
  to an intermediary form used in the AST. They will still be placed
  in the right module attributes, however.
  """
  # @todo (Erlang Recon) Figure out a way to pretty-print typespecs
  # and records.
  @spec source(module) :: iolist
  def source(module), do: :recon.source(module)

  # Ports Info   #

  @doc """
  Returns a list of all TCP ports (the data type) open on the node.
  """
  @spec tcp :: [port]
  def tcp(), do: :recon.tcp()

  @doc """
  Returns a list of all UDP ports (the data type) open on the node.
  """
  @spec udp :: [port]
  def udp(), do: :recon.udp()

  @doc """
  Returns a list of all SCTP ports (the data type) open on the node.
  """
  @spec sctp :: [port]
  def sctp(), do: :recon.sctp()

  @doc """
  Returns a list of all file handles open on the node.
  """
  @spec files :: [port]
  def files(), do: :recon.files()

  @doc """
  Shows a list of all different ports on the node with their
  respective types.
  """
  @spec port_types :: [{type :: charlist, count :: pos_integer}]
  def port_types(), do: :recon.port_types()

  @doc """
  Fetches a given attribute from all inet ports (TCP, UDP, SCTP) and
  returns the biggest `num` consumers.

  The values to be used can be the number of octets (bytes) sent,
  received, or both (`:send_oct`, `~recv_oct`, `:oct`, respectively),
  or the number of packets sent, received, or both (`:send_cnt`,
  `:recv_cnt`, `:cnt`, respectively). Individual absolute values for
  each metric will be returned in the 3rd position of the resulting
  tuple.
  """
  # @todo Implement this function so it only stores `Num' entries in
  # memory at any given time, instead of as many as there are
  # processes.
  @spec inet_count(inet_attr_name, non_neg_integer) :: [inet_attrs]
  def inet_count(attr, num), do: :recon.inet_count(attr, num)

  @doc """
  Fetches a given attribute from all inet ports (TCP, UDP, SCTP) and
  returns the biggest entries, over a sliding time window.

  **Warning:** this function depends on data gathered at two
  snapshots, and then building a dictionary with entries to
  differentiate them. This can take a heavy toll on memory when you
  have many dozens of thousands of ports open.

  The values to be used can be the number of octets (bytes) sent,
  received, or both (`:send_oct`, `:recv_oct`, `:oct`, respectively),
  or the number of packets sent, received, or both (`:send_cnt`,
  `:recv_cnt`, `:cnt`, respectively). Individual absolute values for
  each metric will be returned in the 3rd position of the resulting
  tuple.
  """
  @spec inet_window(inet_attr_name, non_neg_integer, time_ms) :: [inet_attrs]
  def inet_window(attr, num, time) when is_atom(attr) do
    :recon.inet_window(attr, num, time)
  end

  @doc """
  Allows to be similar to `:erlang.port_info/1`, but allows more
  flexible port usage: usual ports, ports that were registered locally
  (an atom), ports represented as strings (`"#Port<0.2013>"`),

  or through an index lookup (`2013`, for the same result as
  `"#Port<0.2013>"`).

  Moreover, the function will try to fetch implementation-specific
  details based on the port type (only inet ports have this feature so
  far). For example, TCP ports will include information about the
  remote peer, transfer statistics, and socket options being used.

  The information-specific and the basic port info are sorted and
  categorized in broader categories (`port_info_type()`).
  """
  @spec port_info(port_term) ::
          [{port_info_type, [{port_info_key, term}]}, ...]
  def port_info(port_term) do
    ReconLib.term_to_port(port_term) |> :recon.port_info()
  end

  @doc """
  Allows to be similar to `:erlang.port_info/2`, but allows more
  flexible port usage: usual ports, ports that were registered locally
  (an atom), ports represented as strings (`"#Port<0.2013>"`),
  or through an index lookup (`2013', for the same result as
  `"#Port<0.2013>"`).

  Moreover, the function allows to to fetch information by category as
  defined in `port_info_type()`, and although the type signature
  doesn't show it in the generated documentation, individual items
  accepted by `:erlang.port_info/2` are accepted, and lists of them
  too.
  """
  @spec port_info(port_term, port_info_type) ::
          {port_info_type, [{port_info_key, term}]}
  @spec port_info(port_term, [atom]) :: [{atom, term}]
  @spec port_info(port_term, atom) :: {atom, term}
  def port_info(port_term, type_or_keys) when is_binary(port_term) do
    to_charlist(port_term) |> :recon.port_info(type_or_keys)
  end

  def port_info(port_term, type_or_keys) do
    :recon.port_info(port_term, type_or_keys)
  end

  ### RPC Utils ###

  @doc """
  Shorthand for `rpc([node()|nodes()], fun)`
  """
  @spec rpc((-> term)) :: rpc_result
  def rpc(fun), do: :recon.rpc(fun)

  @doc """
  Shorthand for `rpc(nodes, fun, :infinity)`
  """
  @spec rpc(nodes, (-> term)) :: rpc_result
  def rpc(nodes, fun), do: :recon.rpc(nodes, fun)

  @doc """
  Runs an arbitrary fn (of arity 0) over one or more nodes.
  """
  @spec rpc(nodes, (-> term), timeout_ms) :: rpc_result
  def rpc(nodes, fun, timeout), do: :recon.rpc(nodes, fun, timeout)

  @doc """
  Shorthand for `named_rpc([node()|nodes()], fun)`
  """
  @spec named_rpc((-> term)) :: rpc_result
  def named_rpc(fun), do: :recon.named_rpc(fun)

  @doc """
  Shorthand for `named_rpc(nodes, fun, :infinity)`
  """
  @spec named_rpc(nodes, (-> term)) :: rpc_result
  def named_rpc(nodes, fun), do: :recon.named_rpc(nodes, fun)

  @doc """
  Runs an arbitrary fun (of arity 0) over one or more nodes, and
  returns the name of the node that computed a given result along with
  it, in a tuple.
  """
  @spec named_rpc(nodes, (-> term), timeout_ms) :: rpc_result
  def named_rpc(nodes, fun, timeout), do: :recon.named_rpc(nodes, fun, timeout)
end
