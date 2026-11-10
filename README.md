# CS 422 Assignment 4

This repository contains the code and report for the fourth CS 422 assignment on maximum concurrent flow and network topology design.

## Setup

Python 3.12 or later, [Typst](https://github.com/typst/typst#installation), and a Gurobi license supporting the full model are required. A free [academic license](https://www.gurobi.com/academia/academic-program-and-licenses/) is sufficient, while the bundled size-limited license is too small for the eight-node model.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

Typst must be installed and available as `typst`. Activate the Gurobi license before running the script.

## Run

From the repository root:

```bash
.venv/bin/python assignment4.py
```

This solves the five report examples and the fixed-topology comparison, checks the returned routings, and generates the solutions, solver logs, topology figure, and report in `results/`. Each run overwrites those generated files.

To solve another eight-node traffic matrix:

```bash
.venv/bin/python assignment4.py inputs/cyclic_8.json
```

The input is a JSON array with eight rows and eight columns. Entries must be nonnegative, the diagonal must be zero, and each row and column must sum to at most four. The result is written to `results/custom-solution.json`, with solver output in `results/custom-solver.log`.

## Files

```text
assignment4.py                  topology construction, optimization, and report generation
inputs/                         eight-node traffic matrices
report.typ                      report source
requirements.txt                Python dependencies
results/                        generated solutions, solver logs, figure, and report
```

`solutions.json` supplies values to the [Typst report](results/assignment-4-report.pdf).
