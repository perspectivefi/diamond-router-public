# Audits

## Certora — Spectra Bridge, May 2026

[`2026-05-Certora-Spectra-Bridge.pdf`](./2026-05-Certora-Spectra-Bridge.pdf)

Security assessment carried out by [Certora](https://www.certora.com/) between
**1 and 18 May 2026**.

### Scope

This report covers the wider Spectra Bridge engagement, of which the
DiamondRouter was one component. The review was performed against a monorepo
snapshot that vendored the DiamondRouter alongside the Stellar bridge, the
Stellar oracles, and the Spectra router. The following DiamondRouter files were
in scope:

```
src/DiamondRouter.sol
src/modules/CommandInfoModule.sol
src/modules/CommandsModule.sol
src/modules/FunctionInfoModule.sol
src/modules/FunctionManagerModule.sol
src/modules/libraries/LibExecutionModule.sol
src/modules/libraries/LibFunctionManager.sol
src/modules/libraries/LibModuleManager.sol
src/upgradeInitializers/DiamondMultiInit.sol
```

The `src/` tree published in this repository is byte-for-byte identical to the
DiamondRouter sources as reviewed at the final audited revision.

### Findings

Thirteen findings were reported across the whole engagement: **no Critical and
no High severity issues**, four Medium, six Low, and three Informational.

One finding was filed against a DiamondRouter file:

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| L-02 | Inconsistent usage of transaction value | Low | Fixed |

L-02 concerned `src/modules/CommandsModule.sol`, where the cached
`LibExecutionModule.getMsgValue()` did not reflect native value already spent
earlier in a batch, and was not propagated across nested flashloan calls. The
fix is included in the code published here.

The remaining findings apply to the bridge, oracle, and Stellar components
covered by the same report, which live outside this repository.
