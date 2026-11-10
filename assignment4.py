import argparse
import json
import math
from pathlib import Path
import subprocess
import sys

import gurobipy as gp
from gurobipy import GRB


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results"


def validate_matrix(traffic, degree):
    if not isinstance(traffic, list):
        raise ValueError("The traffic matrix must be a list of rows")
    n = len(traffic)
    if n < 2 or type(degree) is not int or not 1 <= degree < n:
        raise ValueError("Require n >= 2 and an integer degree between 1 and n-1")
    if any(not isinstance(row, list) or len(row) != n for row in traffic):
        raise ValueError("The traffic matrix must be square")
    for i, row in enumerate(traffic):
        if any(isinstance(v, bool) or not isinstance(v, (int, float))
               or not math.isfinite(v) or v < 0 for v in row):
            raise ValueError("Traffic entries must be finite nonnegative numbers")
        if row[i] != 0:
            raise ValueError("Diagonal traffic entries must be zero")
    if any(sum(row) > degree + 1e-10 for row in traffic):
        raise ValueError("A source exceeds its outgoing hose bound")
    if any(sum(traffic[i][j] for i in range(n)) > degree + 1e-10
           for j in range(n)):
        raise ValueError("A destination exceeds its incoming hose bound")


def uniform_matrix(n, degree):
    if type(n) is not int or type(degree) is not int or n < 2 or not 1 <= degree < n:
        raise ValueError("Require n >= 2 and an integer degree between 1 and n-1")
    return [[0 if i == j else degree / (n - 1) for j in range(n)]
            for i in range(n)]


def solve(traffic, degree, edges=None, log=None):
    validate_matrix(traffic, degree)
    n = len(traffic)
    nodes = range(n)
    arcs = [(i, j) for i in nodes for j in nodes if i != j]
    pairs = [(s, t) for s in nodes for t in nodes if s != t]
    if edges is not None:
        chosen = set(map(tuple, edges))
        if (len(chosen) != len(edges) or not chosen.issubset(arcs)
                or any(sum(i == v for i, j in chosen) != degree
                       or sum(j == v for i, j in chosen) != degree for v in nodes)):
            raise ValueError("Fixed edges must form a simple directed d-regular graph")
        arcs = sorted(chosen)
    if not any(v > 0 for row in traffic for v in row):
        return {"n": n, "degree": degree, "traffic": traffic,
                "status": "unbounded_zero_demand", "throughput": None,
                "edges": sorted(edges if edges is not None else
                                [(i, (i + k) % n) for i in nodes
                                 for k in range(1, degree + 1)]),
                "flows": [], "carried_traffic": 0}

    with gp.Env(empty=True) as env:
        env.setParam("OutputFlag", 0)
        env.start()
        with gp.Model("concurrent_flow", env=env) as model:
            model.Params.Threads = 2
            model.Params.MIPGap = 1e-9
            model.Params.MIPGapAbs = 1e-9
            model.Params.FeasibilityTol = 1e-9
            model.Params.IntFeasTol = 1e-9
            if log is not None:
                Path(log).write_text("")
                model.Params.LogFile = str(log)
                model.Params.LogToConsole = 0
                model.Params.OutputFlag = 1
            link = (model.addVars(arcs, vtype=GRB.BINARY, name="link")
                    if edges is None else {arc: 1 for arc in arcs})
            flow = model.addVars([(s, t, i, j) for s, t in pairs for i, j in arcs],
                                 lb=0, name="flow")
            scale = model.addVar(lb=0, name="throughput")
            if traffic == uniform_matrix(n, degree):
                # Direct pairs use at least one hop; all other pairs use at least two.
                model.addConstr(scale <= (n - 1) / (2 * (n - 1) - degree),
                                name="uniform_capacity_bound")
            if edges is None:
                for v in nodes:
                    model.addConstr(gp.quicksum(link[v, j] for j in nodes if j != v)
                                    == degree, name=f"out_degree_{v}")
                    model.addConstr(gp.quicksum(link[i, v] for i in nodes if i != v)
                                    == degree, name=f"in_degree_{v}")
            for i, j in arcs:
                model.addConstr(gp.quicksum(flow[s, t, i, j] for s, t in pairs) <= link[i, j],
                                name=f"capacity_{i}_{j}")
            for s, t in pairs:
                for v in nodes:
                    # A source injects its demand, its destination absorbs it,
                    # and every other node forwards without creating traffic.
                    balance = traffic[s][t] * (int(v == s) - int(v == t))
                    outgoing = gp.quicksum(flow[s, t, i, j] for i, j in arcs if i == v)
                    incoming = gp.quicksum(flow[s, t, i, j] for i, j in arcs if j == v)
                    model.addConstr(outgoing - incoming == scale * balance,
                                    name=f"balance_{s}_{t}_{v}")
            model.setObjective(scale, GRB.MAXIMIZE)
            model.optimize()
            if model.Status != GRB.OPTIMAL:
                raise RuntimeError(f"Solver did not certify optimality (status {model.Status})")
            result = {"n": n, "degree": degree, "traffic": traffic,
                      "status": "optimal", "throughput": scale.X,
                      "best_bound": model.ObjBound if model.IsMIP else model.ObjVal,
                      "gap": model.MIPGap if model.IsMIP else 0,
                      "seconds": model.Runtime, "variables": model.NumVars,
                      "constraints": model.NumConstrs,
                      "gurobi_version": ".".join(map(str, gp.gurobi.version())),
                      "feasibility_tolerance": model.Params.FeasibilityTol,
                      "edges": [[i, j] for i, j in arcs
                                if edges is not None or link[i, j].X > 0.5],
                      "flows": [[s, t, i, j, flow[s, t, i, j].X]
                                for s, t in pairs for i, j in arcs
                                if flow[s, t, i, j].X > 0
                                and (edges is not None or link[i, j].X > 0.5)],
                      "carried_traffic": scale.X * sum(map(sum, traffic))}
            return result


def construct_uniform(n, degree):
    traffic = uniform_matrix(n, degree)
    if degree == 1:
        edges = [(i, (i + 1) % n) for i in range(n)]
        construction = "directed_cycle"
        bound = 2 / n
    elif degree == n - 1:
        edges = [(i, j) for i in range(n) for j in range(n) if i != j]
        construction = "complete_directed_graph"
        bound = 1
    elif n == 2 * degree:
        edges = [(i, j) for i in range(n) for j in range(n)
                 if (i < degree) != (j < degree)]
        construction = "bidirectional_complete_bipartite"
        bound = (n - 1) / (2 * (n - 1) - degree)
    elif (n, degree) == (5, 2):
        edges = [(i, (i + step) % n) for i in range(n) for step in (-1, 1)]
        construction = "bidirectional_five_cycle"
        bound = 2 / 3
    else:
        # The same pair-flow model constructs an optimum for general n,d.
        result = solve(traffic, degree)
        result["construction"] = "pair_flow_milp"
        return result
    result = solve(traffic, degree, edges=edges)
    if abs(result["throughput"] - bound) > 1e-7:
        raise RuntimeError("Constructed routing did not attain its proved bound")
    result["construction"] = construction
    result["global_upper_bound"] = bound
    return result


def check_solution(result):
    traffic, n, degree = result["traffic"], result["n"], result["degree"]
    validate_matrix(traffic, degree)
    arcs = set(map(tuple, result["edges"]))
    if (len(arcs) != len(result["edges"]) or len(arcs) != n * degree
            or any(i == j or not (0 <= i < n and 0 <= j < n) for i, j in arcs)):
        raise ValueError("Invalid selected links")
    for v in range(n):
        if sum(i == v for i, j in arcs) != degree or sum(j == v for i, j in arcs) != degree:
            raise ValueError("Selected links violate a degree constraint")
    if result["status"] == "unbounded_zero_demand":
        if any(value != 0 for row in traffic for value in row):
            raise ValueError("Only zero demand has this special status")
        return {"maximum_balance_error": 0, "maximum_capacity_violation": 0}
    scale = result["throughput"]
    if not math.isfinite(scale) or scale < 0:
        raise ValueError("Invalid common multiplier")
    load = dict.fromkeys(arcs, 0.0)
    balance = {(s, t): [0.0] * n for s in range(n) for t in range(n) if s != t}
    seen = set()
    for s, t, i, j, value in result["flows"]:
        if ((s, t, i, j) in seen or (i, j) not in arcs or (s, t) not in balance
                or not math.isfinite(value) or value < -1e-8):
            raise ValueError("Invalid saved flow")
        seen.add((s, t, i, j))
        load[i, j] += value
        balance[s, t][i] += value
        balance[s, t][j] -= value
    error = 0
    for s, t in balance:
        for v in range(n):
            expected = scale * traffic[s][t] * (int(v == s) - int(v == t))
            error = max(error, abs(balance[s, t][v] - expected))
    excess = max(0, max(load.values()) - 1)
    if error > 1e-7 or excess > 1e-7:
        raise ValueError(f"Saved routing is invalid: balance {error}, capacity {excess}")
    return {"maximum_balance_error": error, "maximum_capacity_violation": excess}


def draw_examples(results):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import networkx as nx

    fig, axes = plt.subplots(1, 2, figsize=(8, 2.3))
    graph = nx.DiGraph()
    graph.add_edges_from(results["uniform_5"]["edges"])
    order = nx.cycle_basis(graph.to_undirected())[0]
    nx.draw_networkx(graph, nx.circular_layout(order), ax=axes[0], node_color="white",
                     edgecolors="black", node_size=350, font_size=10, arrowsize=10,
                     width=0.8, connectionstyle="arc3,rad=0.10")
    axes[0].set_title("Uniform traffic (n = 5, d = 2)", fontsize=10)
    axes[0].set_axis_off()
    # Show the explicit routing proved in the report, not a particular MILP optimum.
    paths = [[0, 4], [0, 5, 1, 4], [0, 6, 2, 4], [0, 7, 3, 4]]
    routing = nx.DiGraph()
    for path in paths:
        routing.add_edges_from(zip(path, path[1:]))
    positions = {0: (0, 0.8), 4: (3, 0.8),
                 5: (1, 0.3), 1: (2, 0.3),
                 6: (1, -0.5), 2: (2, -0.5),
                 7: (1, -1.3), 3: (2, -1.3)}
    nx.draw_networkx(routing, positions, ax=axes[1], node_color="white",
                     edgecolors="black", node_size=300, font_size=10,
                     arrowsize=12, width=0.8)
    axes[1].set_title("Four paths carrying one unit each", fontsize=10)
    axes[1].set_axis_off()
    fig.tight_layout()
    fig.savefig(RESULTS / "topologies.pdf", bbox_inches="tight")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description="Construct a topology maximizing concurrent flow")
    parser.add_argument("matrix", nargs="?", type=Path,
                        help="JSON n=8,d=4 matrix; omit to reproduce the report")
    args = parser.parse_args()
    RESULTS.mkdir(exist_ok=True)
    if args.matrix:
        traffic = json.loads(args.matrix.read_text())
        if not isinstance(traffic, list) or len(traffic) != 8:
            raise ValueError("Part 2 requires an 8 by 8 matrix")
        result = solve(traffic, 4, log=RESULTS / "custom-solver.log")
        result["checks"] = check_solution(result)
        (RESULTS / "custom-solution.json").write_text(json.dumps(result, indent=2) + "\n")
        print(f"{result['status']}: multiplier {result['throughput']}")
        return
    results = {"uniform_5": construct_uniform(5, 2),
               "uniform_7": construct_uniform(7, 2)}
    for path in sorted((ROOT / "inputs").glob("*.json")):
        name = path.stem
        results[name] = solve(json.loads(path.read_text()), 4,
                              log=RESULTS / f"{name}-solver.log")
    bipartite_edges = [(i, j) for i in range(8) for j in range(8)
                       if (i < 4) != (j < 4)]
    results["cyclic_8_bipartite"] = solve(results["cyclic_8"]["traffic"], 4,
                                         edges=bipartite_edges)
    for name, result in results.items():
        result["checks"] = check_solution(result)
        print(f"{name}: θ={result['throughput']:.9f}; checks passed")
    (RESULTS / "solutions.json").write_text(json.dumps(results, indent=2) + "\n")
    draw_examples(results)
    subprocess.run(["typst", "compile", "--root", str(ROOT), str(ROOT / "report.typ"),
                    str(RESULTS / "assignment-4-report.pdf")], check=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, gp.GurobiError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
