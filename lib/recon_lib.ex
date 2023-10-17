defmodule ReconLib do
  require :recon_lib

  @moduledoc """
  Regroups useful functionality used by recon when dealing with data
  from the node. The functions in this module allow quick runtime
  access to fancier behaviour than what would be done using recon
  module itself.
  """

  @type diff :: [Recon.proc_attrs() | Recon.inet_attrs()]
  @type milliseconds :: non_neg_integer
  @type interval_ms :: non_neg_integer

  @type scheduler_id :: pos_integer
  @type sched_time ::
          {scheduler_id, active_time :: non_neg_integer, total_time :: non_neg_integer}

  @doc """
  Compare two samples and return a list based on some key. The type
  mentioned for the structure is `diff()` (`{key, val, other}`), which
  is compatible with the `Recon.proc_attrs()` type.
  """
  @spec sliding_window(first :: diff, last :: diff) :: diff
  def sliding_window(first, last) do
    :recon_lib.sliding_window(first, last)
  end

  @doc """
  Runs a fun once, waits `ms`, runs the fun again, and returns both
  results.
  """
  @spec sample(milliseconds, (-> term)) ::
          {first :: term, second :: term}
  def sample(delay, fun), do: :recon_lib.sample(delay, fun)

  @doc """
  Takes a list of terms, and counts how often each of them appears in
  the list. The list returned is in no particular order.
  """
  @spec count([term]) :: [{term, count :: integer}]
  def count(terms), do: :recon_lib.count(terms)

  @doc """
  Returns a list of all the open ports in the VM, coupled with
  one of the properties desired from `:erlang.port_info/1` and
  `:erlang.port_info/2`
  """
  @spec port_list(attr :: atom) :: [{port, term}]
  def port_list(attr), do: :recon_lib.port_list(attr)

  @doc """
  Returns a list of all the open ports in the VM, but only if the
  `attr`'s resulting value matches `val`. `attr` must be a property
  accepted by `:erlang.port_info/2`.
  """
  @spec port_list(attr :: atom, term) :: [port]
  def port_list(attr, val), do: :recon_lib.port_list(attr, val)

  @doc """
  Returns the attributes (`Recon.proc_attrs/0`) of all processes of
  the node, except the caller.
  """
  @spec proc_attrs(term) :: [Recon.proc_attrs()]
  def proc_attrs(attr_name) do
    :recon_lib.proc_attrs(attr_name)
  end

  @doc """
  Returns the attributes of a given process. This form of attributes
  is standard for most comparison functions for processes in recon.

  A special attribute is `binary_memory`, which will reduce the memory
  used by the process for binary data on the global heap.
  """
  @spec proc_attrs(term, pid) :: {:ok, Recon.proc_attrs()} | {:error, term}
  def proc_attrs(attr_name, pid) do
    :recon_lib.proc_attrs(attr_name, pid)
  end

  @doc """
  Returns the attributes (Recon.inet_attrs/0) of all inet ports (UDP,
  SCTP, TCP) of the node.
  """
  @spec inet_attrs(term) :: [Recon.inet_attrs()]
  def inet_attrs(attr_name), do: :recon_lib.inet_attrs(attr_name)

  @doc """
  Returns the attributes required for a given inet port (UDP, SCTP,
  TCP). This form of attributes is standard for most comparison
  functions for processes in recon.
  """
  @spec inet_attrs(Recon.inet_attri_name(), port) ::
          {:ok, Recon.inet_attrs()} | {:error, term}
  def inet_attrs(attr, port), do: :recon_lib.inet_attrs(attr, port)

  @doc """
  Equivalent of `pid(x, y, z)` in the Elixir's iex shell.
  """
  @spec triple_to_pid(non_neg_integer, non_neg_integer, non_neg_integer) :: pid
  def triple_to_pid(x, y, z), do: :recon_lib.triple_to_pid(x, y, z)

  @doc """
  Transforms a given term to a pid.
  """
  @spec term_to_pid(Recon.pid_term()) :: pid
  def term_to_pid(term) do
    pre_process_pid_term(term) |> :recon_lib.term_to_pid()
  end

  defp pre_process_pid_term({_a, _b, _c} = pid_term) do
    pid_term
  end

  defp pre_process_pid_term(<<"#PID", pid_term::binary>>) do
    to_charlist(pid_term)
  end

  defp pre_process_pid_term(pid_term) when is_binary(pid_term) do
    to_charlist(pid_term)
  end

  defp pre_process_pid_term(pid_term) do
    pid_term
  end

  @doc """
  Transforms a given term to a port.
  """
  @spec term_to_port(Recon.port_term()) :: port
  def term_to_port(term) when is_binary(term) do
    to_charlist(term) |> :recon_lib.term_to_port()
  end

  def term_to_port(term) do
    :recon_lib.term_to_port(term)
  end

  @doc """
  Calls a given function every `interval` milliseconds and supports
  a map-like interface (each result is modified and returned)
  """
  @spec time_map(
          n :: non_neg_integer,
          interval_ms,
          fun :: (state :: term -> {term, state :: term}),
          initial_state :: term,
          mapfun :: (term -> term)
        ) :: [term]
  def time_map(n, interval, fun, state, map_fun) do
    :recon_lib.time_map(n, interval, fun, state, map_fun)
  end

  @doc """
  Calls a given function every `interval` milliseconds and supports
  a fold-like interface (each result is modified and accumulated)
  """
  @spec time_fold(
          n :: non_neg_integer,
          interval_ms,
          fun :: (state :: term -> {term, state :: term}),
          initial_state :: term,
          foldfun :: (term, acc0 :: term -> acc1 :: term),
          initial_acc :: term
        ) :: [term]
  def time_fold(n, interval, fun, state, fold_fun, init) do
    :recon_lib.time_fold(n, interval, fun, state, fold_fun, init)
  end

  @doc """
  Diffs two runs of :erlang.statistics(scheduler_wall_time) and
  returns usage metrics in terms of cores and 0..1 percentages.
  """
  @spec scheduler_usage_diff(sched_time, sched_time) ::
          [{scheduler_id, usage :: number}]
  def scheduler_usage_diff(first, last) do
    :recon_lib.scheduler_usage_diff(first, last)
  end
end
