# ReconEx

ReconEx is an Elixir wrapper for [Recon](https://ferd.github.io/recon/).
It is a library to be dropped into any other Elixir project, to be
used to assist DevOps people diagnose problems from `iex` shell in
production Erlang VMs.

Included modules are:

- **Recon**
  * gathers information about processes and the general state of
    the VM, ports, and OTP behaviours running in the node.

- **ReconAlloc**
  * provides functions to deal with Erlang's memory allocators.

- **ReconLib**
  * provides useful functionality used by Recon when dealing
    with data from the node.

- **ReconTrace**
  * production-safe tracing facilities.

Documentation for the library can be obtained at
https://hex.pm/packages/recon_ex (**TODO**)

It is recommended that you use tags (**TODO**: create tags) if you do
not want bleeding edge and development content for this library.


## Current Status

Versions supported:

- Elixir 1.1 or newer
- Recon 2.5.0 or newer


## Try Them Out

To build the library:

```shell-session
mix deps.get
mix compile
iex -S mix
```

**TODO**: Some examples.


## Install As Dependency

**TODO**


## Change Log

**TODO**


## Special Thanks

- Special thanks to Fred Hebert, the author of [Recon](https://ferd.github.io/recon/),
  and the all contributors to it.


## License

This code, as the original Recon, is published under the BSD 3-clause
License. See LICENSE file for more information.
