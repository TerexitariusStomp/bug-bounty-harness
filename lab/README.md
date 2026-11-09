# lab/ — verification fixtures

Safe local targets used by canary-update smoke tests and bb-bench.

## web

```bash
docker run -d --name lab-juice -p 127.0.0.1:3000:3000 bkimminich/juice-shop
```

`scope/targets.yaml` already points `lab-local` at `127.0.0.1:3000`.

## contracts

```bash
git clone --depth 1 https://github.com/crytic/damn-vulnerable-defi lab/dvd
git clone --depth 1 https://github.com/OpenZeppelin/ethernaut   lab/ethernaut
```

Register `lab/dvd` in `scope/contracts.yaml` (lang: solidity, fuzz: false).

## agent benches (bb-bench pulls these)

- KeygraphHQ/xbow-validation-benchmarks — 104 hint-free web challenges
- BountyBench — dollar-impact detect/exploit/patch tasks
- CVE-Bench — 40 real CVEs, one-day mode
