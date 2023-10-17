defmodule ReconTraceTest do
  use ExUnit.Case
  # doctest ReconTrace

  import ReconTrace, only: [to_erl_tspec: 1, format: 1]

  test "to_erl_tspec/1" do
    shellfun = make_shellfun("fn([n, _]) when n > 10 -> :ok end")
    matchspec = [{[:"$1", :_], [{:>, :"$1", 10}], [:ok]}]

    assert to_erl_tspec({:queue, :in, shellfun}) == {:queue, :in, matchspec}
    assert to_erl_tspec({:queue, :in, matchspec}) == {:queue, :in, matchspec}
    assert to_erl_tspec({:queue, :in, 2}) == {:queue, :in, 2}

    shellfun = make_shellfun("fn([:item, _]) -> :return end")
    matchspec = [{[:item, :_], [], [{:return_trace}]}]

    assert to_erl_tspec({:queue, :in, shellfun}) == {:queue, :in, matchspec}
  end

  test "format/1 for :call" do
    ts = :os.timestamp()

    # Format an Elixir module call with atom and function
    assert format(
             {:trace_ts, pid(0, 1, 2), :call, {Emum, :each, [[:hello, "world"], &IO.puts/1]}, ts}
           ) ==
             ~c"\n#{format_timestamp(ts)} <0.1.2> Emum.each([:hello, \"world\"], &IO.puts/1)\n"

    # Format an Erlang module call
    assert format({:trace_ts, pid(0, 1, 2), :call, {:lists, :seq, [1, 10]}, ts}) ==
             ~c"\n#{format_timestamp(ts)} <0.1.2> :lists.seq(1, 10)\n"
  end

  test "format/1 for :return_to" do
    ts = :os.timestamp()

    assert format({:trace_ts, pid(0, 1, 2), :return_from, {Emum, :each, 2}, :ok, ts}) ==
             ~c"\n#{format_timestamp(ts)} <0.1.2> Emum.each/2 --> :ok\n"
  end

  #################
  ### Utilities ###
  #################

  @spec make_shellfun(binary) :: ([term] -> term)
  defp make_shellfun(fun_str) do
    to_charlist(fun_str) |> Code.eval_string([]) |> elem(0)
  end

  # defp make_shellfun_erl(erl_fun_str) do
  #   {:ok, tokens, _} = to_char_list(erl_fun_str) |> :erl_scan.string
  #   {:ok, [expr]} = :erl_parse.parse_exprs(tokens)
  #   {:value, shellfun, _} = :erl_eval.expr(expr, [])
  #   shellfun
  # end

  defp pid(a, b, c) do
    :erlang.list_to_pid(~c"<#{a}.#{b}.#{c}>")
  end

  defp to_hms({_, _, micro} = ts) do
    {_, {h, m, secs}} = :calendar.now_to_local_time(ts)
    seconds = rem(secs, 60) + micro / 1_000_000
    {h, m, seconds}
  end

  defp format_hms({h, m, s}) do
    :io_lib.format(~c"~2.2.0w:~2.2.0w:~9.6.0f", [h, m, s])
  end

  defp format_timestamp(ts) do
    to_hms(ts) |> format_hms
  end
end
