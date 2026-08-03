# Third Party Notices

The Spectra DiamondRouter is licensed under the Business Source License 1.1
(see [LICENSE](./LICENSE)). The files listed below are **not** covered by that
license. They are derived from third-party work and remain under the MIT
License of their respective authors, as marked by the `SPDX-License-Identifier: MIT`
header in each file.

## OpenZeppelin Contracts

Copyright (c) 2016-2025 Zeppelin Group Ltd — MIT License
<https://github.com/OpenZeppelin/openzeppelin-contracts>

Files in this repository derived from OpenZeppelin Contracts v5.x, modified by
Spectra to use `AccessManager` in place of `Ownable` for access control:

- `src/proxy/AMProxyAdmin.sol` — from `proxy/transparent/ProxyAdmin.sol`
- `src/proxy/AMTransparentUpgradeableProxy.sol` — from `proxy/transparent/TransparentUpgradeableProxy.sol`

OpenZeppelin Contracts and OpenZeppelin Contracts Upgradeable (`5.4.0-rc.1`)
are also build-time dependencies, resolved via Soldeer and not vendored here.

## EIP-2535 Diamonds reference implementation

Copyright (c) Nick Mudge \<nick@perfectabstractions.com\> — MIT License
<https://eips.ethereum.org/EIPS/eip-2535>

Files in this repository derived from the EIP-2535 Diamonds reference
implementation:

- `src/upgradeInitializers/DiamondMultiInit.sol`
- `src/modules/libraries/LibModuleManager.sol`
- `src/modules/libraries/LibFunctionManager.sol`

## ERC interface definitions

- `src/interfaces/IERC165.sol` — ERC-165 Standard Interface Detection
- `src/interfaces/IERC173.sol` — ERC-173 Contract Ownership Standard

## Development dependencies

`forge-std` (`1.9.7`), dual-licensed MIT / Apache-2.0, is a test-time
dependency resolved via Soldeer and not vendored here.

---

## MIT License

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
