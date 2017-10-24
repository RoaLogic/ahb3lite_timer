# AHB-Lite Timer

The Roa Logic AHB-Lite Timer IP is a fully parameterized soft IP implementing a user-defined number of timers and functions as specified by the RISC-V Privileged 1.9.1 specification.

The IP features an AHB-Lite Slave interface, with all signals defined in the *AMBA 3 AHB-Lite v1.0* specifications fully supported, supporting a single AHB-Lite based host connection. Bus address & data widths as well as the number of timers supported are specified via parameters.

The timebase of the timers is derived from the AHB-Lite bus clock, scaled down by a programmable value.

The module features a single Interrupt output which is asserted whenever an enabled timer is triggered

![Example Implementation](assets/img/AHB-Lite-Timer-sig.png)

## Documentation

- [Datasheet](DATASHEET.md)
  - [PDF Format](docs/ahb3lite_timer_datasheet.pdf)

## Features

- AHB-Lite Interface with programmable address and data width
- User defined number of counters (Up to 32)
- Programmable time base derived from AHB-Lite bus clock

## Compatibility

Compliant to the RISC-V Privilege Level 1.9, 1.9.1, 1.10 specifications

## Interfaces

- AHB-Lite

## License

Released under the RoaLogic [Non-Commercial License](/LICENSE.md)

## Dependencies

Requires the Roa Logic [AHB3Lite Package](). This is are included as a submodule.
After cloning the RV12 git repository, perform a 'git submodule init' to download the submodule.
