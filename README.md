# OMO

Bytecode emulator with per-step state proof.
It can be used to generate challenge proof of optimistic rollup,
and other scenarios in blockchain which need state proof.

See more introductions here: [en](docs/overview.md) / [zh](docs/ch/overview.md).

## Platforms

OMO could emulate program built with:

- **Arch**: MIPS32
- **OS**: Linux
- **Executable File Format**: ELF 32-bit MSB

May support more in the future.

### Development Environment

X86-64 Linux & Apple Silicon MacOS.

## Getting Started

The project contains three major Rust crates:

- [`./omo` ](omo): main entrypoint of the OMO emulator.
- [`./rust-mips-example`](rust-mips-example): examples crate. It is configured to build into a linux mips binary, which
  can be run by `OMO`.
- [`./omo-workflow`](omo-workflow): Rust binary to demonstrate how OMO work with onchain contracts to provide
  interacting fraud proof.

### Prerequisites

- [rust](https://rustup.rs/)
- [musl](https://musl.cc)

#### Installing MUSL toolchains

- Add mips-unknown-linux-musl target for rust:

```shell
rustup target add mips-unknown-linux-musl
```

- Download musl toolchain from [musl.cc](https://musl.cc): mips-linux-musl-cross

- For Apple Silicon:

```shell
brew install FiloSottile/musl-cross/musl-cross --without-x86_64 --with-mips
```

### Run Example

**Compile `rust-mips-example`:**

```shell
cargo build --target mips-unknown-linux-musl --release 
```

**Compile `OMO`:**

```shell
cargo build --release
```

**Run Example1:**

```shell
RUST_LOG=error ./omo2 --config config.toml.example run --env E1=a --env E2=b /Users/templex/rooch/omo/target/mips-unknown-linux-musl/release/rust-mips-example E1 E2
```

**Output:**

```
Run rust-mips-example
E1=a
E2=b
```

**Run Example2:**

```shell
RUST_LOG=error ./omo2 --config config.toml.example run /Users/templex/rooch/omo/target/mips-unknown-linux-musl/release/arith-example 1 11
```

**Output:**

```
thread 'main' panicked at 'assertion failed: `(left == right)`
  left: `10`,
 right: `11`: expect 11, but got 10', rust-mips-example/src/arith_example.rs:13:5
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

## License

Distributed under the Apache License 2.0. See [LICENSE](LICENSE) for more information.

## Acknowledgments

- [Cannon](https://github.com/ethereum-optimism/cannon)
- [Unicorn](https://github.com/unicorn-engine/unicorn)
- [Qiling](https://github.com/qilingframework/qiling)
