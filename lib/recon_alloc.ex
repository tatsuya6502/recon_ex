defmodule ReconAlloc do
  require :recon_alloc

  @moduledoc """
  Functions to deal with
  [Erlang VM's memory allocators](http://www.erlang.org/doc/man/erts_alloc.html),
  or particularly, to try to present the allocator data in a way that
  makes it simpler to discover possible problems.

  Tweaking Erlang VM memory allocators and their behaviour is a very
  tricky ordeal whenever you have to give up the default settings.
  This module (and its documentation) will try and provide helpful
  pointers to help in this task.

  This module should mostly be helpful to figure out **if** there is a
  problem, but will offer little help to figure out **what** is wrong.

  To figure this out, you need to dig deeper into the allocator data
  (obtainable with `allocators/0`), and/or have some precise knowledge
  about the type of load and work done by the VM to be able to assess
  what each reaction to individual tweak should be.

  A lot of trial and error might be required to figure out if tweaks
  have helped or not, ultimately.

  In order to help do offline debugging of memory allocator problems
  ReconAlloc also has a few functions that store snapshots of the
  memory statistics.

  These snapshots can be used to freeze the current allocation values
  so that they do not change during analysis while using the regular
  functionality of this module, so that the allocator values can be
  saved, or that they can be shared, dumped, and reloaded for further
  analysis using files. See `snapshot_load/1` for a simple use-case.

  **Glossary:**

  - **sys_alloc**    : System allocator, usually just malloc
  - **mseg_alloc**   : Used by other allocators, can do mmap. Caches
    allocations
  - **temp_alloc**   : Used for temporary allocations
  - **eheap_alloc**  : Heap data (i.e. process heaps) allocator
  - **binary_alloc** : Global binary heap allocator
  - **ets_alloc**    : ETS data allocator
  - **driver_alloc** : Driver data allocator
  - **sl_alloc**     : Short-lived memory blocks allocator
  - **ll_alloc**     : Long-lived data (i.e. Erlang code itself)
    allocator
  - **fix_alloc**    : Frequently used fixed-size data allocator
  - **std_alloc**    : Allocator for other memory blocks
  - **carrier**      :
    When a given area of memory is allocated by the OS to the VM
    (through sys_alloc or mseg_alloc), it is put into a **carrier**.
    There are two kinds of carriers: multiblock and single block. The
    default carriers data is sent to are multiblock carriers, owned by
    a specific allocator (ets_alloc, binary_alloc, etc.). The specific
    allocator can thus do allocation for specific Erlang requirements
    within bits of memory that has been preallocated before. This
    allows more reuse, and we can even measure the cache hit rates
    `cache_hit_rates/0`.

    There is however a threshold above which an item in memory won't
    fit a multiblock carrier. When that happens, the specific
    allocator does a special allocation to a single block carrier.
    This is done by the allocator basically asking for space directly
    from sys_alloc or mseg_alloc rather than a previously multiblock
    area already obtained before.

    This leads to various allocation strategies where you decide to
    choose:

    * which multiblock carrier you're going to (if at all)
    * which block in that carrier you're going to

    See [the official documentation on erts_alloc](http://www.erlang.org/doc/man/erts_alloc.html)
    for more details.
  - **mbcs**  : Multiblock carriers.
  - **sbcs**  : Single block carriers.
  - **lmbcs** : Largest multiblock carrier size
  - **smbcs** : Smallest multiblock carrier size
  - **sbct**  : Single block carrier threshold

  By default all sizes returned by this module are in bytes. You can
  change this by calling `set_unit/1`.
  """

  @type allocator :: :temp_alloc | :eheap_alloc | :binary_alloc | :ets_alloc
                      | :driver_alloc | :sl_alloc | :ll_alloc | :fix_alloc
                      | :std_alloc
  @type instance :: non_neg_integer
  @type allocdata(t) :: {{allocator, instance}, t}

  # Snapshot handling
  @type memory :: [{atom, atom}]
  @type snapshot :: {memory, [allocdata(term)]}


  ############
  # Public   #
  ############

  @doc """
  Equivalent to `memory(key, :current)`.
  """
  @spec memory(:used | :allocated | :unused) :: pos_integer
  @spec memory(:usage) :: number
  @spec memory(:allocated_types | :allocated_instances)
                 :: [{allocator, pos_integer}]
  def memory(key), do: :recon_alloc.memory(key)

  @doc """
  Reports one of multiple possible memory values for the entire
  node depending on what is to be reported:

  - `:used` reports the memory that is actively used for allocated
    Elixir/Erlang data.
  - `:allocated` reports the memory that is reserved by the VM. It
    includes the memory used, but also the memory yet-to-be-used but
    still given by the OS. This is the amount you want if you're
    dealing with ulimit and OS-reported values.
  - `:allocated_types` reports the memory that is reserved by the
    VM grouped into the different util allocators.
  - `:allocated_instances` reports the memory that is reserved by the VM
    grouped into the different schedulers. Note that instance id 0 is
    the global allocator used to allocate data from non-managed
    threads, i.e. async and driver threads.
  - `:unused` reports the amount of memory reserved by the VM that is
    not being allocated. Equivalent to `:allocated - :used`
  - `usage` returns a percentage (0.0 .. 1.0) of `used/allocated`
    memory ratios.

  The memory reported by `:allocated` should roughly match what the OS
  reports. If this amount is different by a large margin, it may be
  the sign that someone is allocating memory in C directly, outside of
  Erlang VM's own allocator -- a big warning sign. There are currently
  three sources of memory alloction that are not counted towards this
  value: The cached segments in the mseg allocator, any memory
  allocated as a super carrier, and small pieces of memory allocated
  during start-up before the memory allocators are initialized.

  Also note that low memory usages can be the sign of fragmentation in
  memory, in which case exploring which specific allocator is at fault
  is recommended (see `fragmentation/1`)
  """
  @spec memory(:used | :allocated | :unused, :current | :max) :: pos_integer
  @spec memory(:usage, :current | :max) :: number
  @spec memory(:allocated_types | :allocated_instances, :current | :max)
                 :: [{allocator, pos_integer}]
  def memory(type, keyword), do: :recon_alloc.memory(type, keyword)

  @doc """
  Compares the block sizes to the carrier sizes, both for single block
  (`sbcs`) and multiblock (`mbcs`) carriers.

  The returned results are sorted by a weight system that is somewhat
  likely to return the most fragmented allocators first, based on
  their percentage of use and the total size of the carriers, for both
  `sbcs` and `mbcs`.

  The values can both be returned for `current' allocator values, and
  for `max` allocator values. The current values hold the present
  allocation numbers, and max values, the values at the peak.
  Comparing both together can give an idea of whether the node is
  currently being at its memory peak when possibly leaky, or if it
  isn't. This information can in turn influence the tuning of
  allocators to better fit sizes of blocks and/or carriers.
  """
  @spec fragmentation(:current | :max) :: [allocdata([{atom, term}])]
  def fragmentation(keyword), do: :recon_alloc.fragmentation(keyword)

  @doc """
  Looks at the `mseg_alloc` allocator (allocator used by all the
  allocators in `allocator/1`) and returns information relative to the
  cache hit rates. Unless memory has expected spiky behaviour, it
  should usually be above 0.80 (80%).

  Cache can be tweaked using three VM flags: `+MMmcs`, `+MMrmcbf`, and
  `+MMamcbf`.

  `+MMmcs` stands for the maximum amount of cached memory segments.
  Its default value is `10` and can be anything from 0 to 30.
  Increasing it first and verifying if cache hits get better should be
  the first step taken.

  The two other options specify what are the maximal values of a
  segment to cache, in relative (in percent) and absolute terms (in
  kilobytes), respectively. Increasing these may allow more segments
  to be cached, but should also add overheads to memory allocation. An
  Erlang node that has limited memory and increases these values may
  make things worse on that point.

  The values returned by this function are sorted by a weight
  combining the lower cache hit joined to the largest memory values
  allocated.
  """
  @spec cache_hit_rates() :: [{{:instance, instance},
                               [{:hit_rate | :hits | :calls, term}]}]
  def cache_hit_rates(), do: :recon_alloc.cache_hit_rates

  @doc """
  Checks all allocators in `allocator/0` and returns the average block
  sizes being used for `mbcs` and `sbcs`. This value is interesting to
  use because it will tell us how large most blocks are. This can be
  related to the VM's largest multiblock carrier size (`lmbcs`) and
  smallest multiblock carrier size (`smbcs`) to specify allocation
  strategies regarding the carrier sizes to be used.

  This function isn't exceptionally useful unless you know you have
  some specific problem, say with sbcs/mbcs ratios (see
  `sbcs_to_mbcs/0`) or fragmentation for a specific allocator, and
  want to figure out what values to pick to increase or decrease sizes
  compared to the currently configured value.

  Do note that values for `lmbcs` and `smbcs` are going to be rounded
  up to the next power of two when configuring them.
  """
  @spec average_block_sizes(:current | :max)
                             :: [{allocator, [{:mbcs, :sbcs, number}]}]
  def average_block_sizes(keyword) do
    :recon_alloc.average_block_sizes(keyword)
  end

  @doc """
  Compares the amount of single block carriers (`sbcs') vs the number
  of multiblock carriers (`mbcs') for each individual allocator in
  `allocator/0`.

  When a specific piece of data is allocated, it is compared to a
  threshold, called the **single block carrier threshold**
  (`sbct`). When the data is larger than the `sbct`, it gets sent to a
  single block carrier. When the data is smaller than the `sbct`, it
  gets placed into a multiblock carrier.

  mbcs are to be prefered to sbcs because they basically represent
  pre-allocated memory, whereas sbcs will map to one call to sys_alloc
  or mseg_alloc, which is more expensive than redistributing data that
  was obtained for multiblock carriers. Moreover, the VM is able to do
  specific work with mbcs that should help reduce fragmentation in
  ways sys_alloc or mmap usually won't.

  Ideally, most of the data should fit inside multiblock carriers. If
  most of the data ends up in `sbcs`, you may need to adjust the
  multiblock carrier sizes, specifically the maximal value (`lmbcs`)
  and the threshold (`sbct`). On 32 bit VMs, `sbct` is limited to
  8MBs, but 64 bit VMs can go to pretty much any practical size.

  Given the value returned is a ratio of sbcs/mbcs, the higher the
  value, the worst the condition. The list is sorted accordingly.
  """
  @spec sbcs_to_mbcs(:max | :current) :: [allocdata(term)]
  def sbcs_to_mbcs(keyword), do: :recon_alloc.sbcs_to_mbcs(keyword)

  @doc """
  Returns a dump of all allocator settings and values.
  """
  @spec allocators() :: [allocdata(term)]
  def allocators(), do: :recon_alloc.allocators

  #######################
  # Snapshot handling   #
  #######################

  @doc """
  Take a new snapshot of the current memory allocator statistics.
  The snapshot is stored in the process dictionary of the calling
  process, with all the limitations that it implies (i.e. no
  garbage-collection). To unsert the snapshot, see
  `snapshot_clear/1`.
  """
  @spec snapshot() :: snapshot | :undefined
  def snapshot(), do: :recon_alloc.snapshot

  @doc """
  Clear the current snapshot in the process dictionary, if present,
  and return the value it had before being unset.
  """
  @spec snapshot_clear() :: snapshot | :undefined
  def snapshot_clear(), do: :recon_alloc.snapshot_clear

  @doc """
  Prints a dump of the current snapshot stored by `snapshot/0`. Prints
  `undefined` if no snapshot has been taken.
  """
  @spec snapshot_print() :: :ok
  def snapshot_print() do
    # @TODO: Need a pretter print?
    # io:format("~p.~n",[snapshot_get()]).  # Note: there is a period
    IO.inspect :recon_alloc.snapshot_get, pretty: true
  end

  @doc """
  Returns the current snapshot stored by `@link snapshot/0`. Returns
  `undefined` if no snapshot has been taken.
  """
  @spec snapshot_get() :: snapshot | :undefined
  def snapshot_get(), do: :recon_alloc.snapshot_get

  @doc """
  Save the current snapshot taken by `snapshot/0` to a file.If there
  is no current snapshot, a snaphot of the current allocator
  statistics will be written to the file.
  """
  @spec snapshot_save(:file.name) :: :ok
  def snapshot_save(filename), do: :recon_alloc.snapshot_save(filename)

  @doc """
  Loads a snapshot from a given file. The format of the data in the
  file can be either the same as output by `snapshot_save/0`, or the
  output obtained by calling Erlang functions, equivalent to the
  following Elixir functions, and storing it in a file in Erlang's
  term format.

  ```
  {:erlang.memory,
   :erlang.system_info(:alloc_util_allocators) ++ [:sys_alloc,:mseg_alloc]
     |> Enum.map &({&1, :erlang.system_info({:allocator, &1})})
  }
  ```

  If the latter option is taken, please remember to add a full stop at
  the end of the resulting Erlang term, as this function uses
  Erlang's `:file.consult/1` to load the file.

  **Example usage:**

  On target machine:

  ```
  iex> ReconAlloc.snapshot
  :undefined
  iex> ReconAlloc.memory(:used)
  18411064
  iex> ReconAlloc.snapshot_save("recon_snapshot.terms")
  :ok
  ```

  On other machine:

  ```
  iex> ReconAlloc.snapshot_load("recon_snapshot.terms")
  :undefined
  iex> ReconAlloc:memory(:used)
  18411064
  ```
  """
  @spec snapshot_load(:file.name) :: snapshot | :undefined
  def snapshot_load(filename), do: :recon_alloc.snapshot_load(filename)

  #######################
  # Handling of units   #
  #######################

  @doc """
  Sets the current unit to be used by recon_alloc. This effects all
  functions that return bytes.

  Eg.

  ```
  iex> ReconAlloc.memory(:used, :current)
  17548752
  iex> ReconAlloc.set_unit(:kilobyte)
  undefined
  iex> ReconAlloc.memory(:used, :current)
  17576.90625
  ```
  """
  @spec set_unit(:byte | :kilobyte | :megabyte | :gigabyte) :: :ok
  def set_unit(unit), do: :recon_alloc.set_unit(unit)

end
