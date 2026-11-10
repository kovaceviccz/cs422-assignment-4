#let results = json("results/solutions.json")
#let repo = "https://github.com/kovaceviccz/cs422-assignment-4"
#let number(x) = str(calc.round(x, digits: 6))
#set document(title: "Maximum Concurrent Flow and Network Design", author: "Marko Kovacevic")
#set page(paper: "us-letter", margin: (x: 0.9in, y: 0.8in), numbering: "1")
#set text(size: 10.5pt)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.")
#set math.equation(numbering: "(1)")
#show figure.caption: set text(size: 9pt)
#show heading.where(level: 1): set block(above: 1.25em, below: 0.65em)

#align(center)[
  #text(17pt, weight: "bold")[Maximum Concurrent Flow and Network Design]
  #v(0.3em)
  Assignment 4

  #v(1em)
  #text(weight: "bold")[Marko Kovacevic]

  CS 42200: Computer Networks \
  Purdue University · Fall 2026 \
  Instructor: Vamsi Addanki \
  TAs: Youngsuk Kim, Xiao Luo, and Albert Vo

  #v(0.6em)
  November 9, 2026
]
#v(1em)

= Introduction

Topology and routing determine how much traffic a network can carry with a fixed
number of links. Short paths use less capacity, but several demands can compete
for the same link. For a traffic matrix $T$, the maximum concurrent flow problem
finds the largest throughput $theta$ for which every requested rate $T_(s t)$,
from source $s$ to destination $t$, can be carried at rate $theta T_(s t)$.

The network consists of $n$ nodes, each with $d$ incoming and $d$ outgoing
links of capacity one. There are no self-links, parallel links, or additional
switches. Nodes can forward traffic, and demands may be split across multiple
paths. Links in opposite directions have separate capacities and are selected
independently.

= Uniform Traffic Matrix

Set $T_(s t)=d/(n-1)$ for $s != t$ and $T_(s s)=0$, with
$n >= 2$ and $1 <= d <= n-1$. Each node therefore requests a total rate of $d$.
The construction applies to every valid $n,d$ and does not require $d$ to
divide $n-1$.

== An upper bound on throughput

There are $n d$ directed links and $n(n-1)$ ordered source–destination pairs.
Exactly $n d$ pairs have a direct link. Every unit delivered to one of those
pairs consumes at least one unit of link capacity, while a pair without a direct
link needs at least two. Summing these minimum link loads over all pairs gives

$ theta d/(n-1) [n d + 2 n(n-1-d)] <= n d, $

and hence

$ theta <= U(n,d) = (n-1)/(2(n-1)-d). $ <uniform-bound>

A two-hop path contributes flow to the load on both links. The cut containing
one source gives $theta <= 1$, but forwarding can impose a stricter bound.
@uniform-bound is a necessary bound. A topology may require longer routes
or have an overloaded cut, so attaining it must be demonstrated.

#pagebreak()
== Optimal constructions

For $n=5,d=2$, connect the nodes in a cycle, with both directed links between
neighbors. The construction is $i -> i-1$ and $i -> i+1$, modulo 5.
At $theta=2/3$, every pair sends $1/3$. Route neighbors directly and all other
pairs along their two-hop shortest path. Each directed link carries one
direct demand and two forwarded demands, giving load $1/3+1/3+1/3=1$.
For example, link $0 -> 1$ carries the demands $0 -> 1$, $0 -> 2$ along
$0 -> 1 -> 2$, and $4 -> 1$ along $4 -> 0 -> 1$. Each contributes $1/3$.
The bound also equals $2/3$, so this cycle is globally optimal.

For $n=2d$, use a complete bipartite topology with both directed links between
every cross-group pair. Each group contains $d$ nodes, and there are no
within-group links. Every node has the required degrees. Send cross-group
demands directly and divide each within-group demand equally among the $d$
intermediate nodes in the other group. At $theta=(2d-1)/(3d-2)$, each pair
sends $r=d/(3d-2)$. The load on every directed link consists of its direct demand,
$d-1$ first-hop contributions, and $d-1$ second-hop contributions.
For a link $u -> v$, with $u in L$ and $v in R$, the first-hop contributions
come from $u$'s demands to the other $d-1$ nodes in $L$. The second-hop
contributions come from the other $d-1$ nodes in $R$ sending to $v$.

$ r + 2(d-1) r/d = 1. $

This throughput equals the upper bound in @uniform-bound, proving the construction optimal.
For $n=8,d=4$, the requested rate is $4/7$ per pair and
$(7/10)(4/7)=2/5$ is delivered. Each split two-hop path carries
$(2/5)/4=1/10$. A directed link carries its direct demand, three first-hop contributions,
and three second-hop contributions. Its total load is

$ 2/5+3(1/10)+3(1/10)=1. $

This proves $theta=7/10$ optimal.

Two boundary cases are also explicit. When $d=1$, positive all-to-all traffic
requires one directed cycle through all $n$ nodes. For each distance
$k=1,dots,n-1$, exactly $k$ source–destination routes cross a given directed
link. Its load is therefore

$ theta/(n-1) sum_(k=1)^(n-1) k = theta n/2. $

Unit link capacity gives $theta <= 2/n$, which the cycle attains.
When $d=n-1$, use the complete directed graph and route directly, giving $theta^*=1$.

== Construction for general parameters

The preceding constructions give explicit optimal topologies for their stated
parameter ranges. For the remaining parameters, solve the formulation in
Section 3 with the uniform traffic matrix. Its binary variables select the
links, and its continuous variables determine the routing. This is a
mixed-integer linear program (MILP).
Fixing the graph leaves a linear program (LP) for the routing.
The model and the following pseudocode specify the general construction.

```text
ConstructUniform(n, d):
    T[s,t] = d/(n-1) if s != t, else 0
    if d == 1: use the directed n-cycle
    else if d == n-1: use the complete directed graph
    else if n == 2*d: use the two-group construction above
    else if (n,d) == (5,2): use the bidirectional five-cycle
    else:
        solve the topology-and-routing MILP in Section 3 for T,n,d
        return its selected links and routing after optimal termination
    solve the fixed-topology flow LP to obtain a routing
    check that its throughput attains the proved upper bound
    return the constructed links and routing
```

A permitted connected topology exists for every valid $n,d$. Selecting
$i -> (i+k) mod n$ for $k=1,dots,d$ gives every node the required degrees and
contains a directed cycle through all nodes, so every source can reach every
destination.

The explicit constructions are optimal by matching a feasible routing to a
capacity bound. For all other parameters, Section 3's model includes every
admissible topology and every feasible fractional routing. An optimal solution
therefore constructs a globally optimal graph.
Gurobi uses
branch-and-bound and can still require substantial time as $n$ grows.

= Arbitrary Traffic Matrix

Set $n=8,d=4$. Let $T$ be a nonnegative $8 times 8$ traffic matrix with zero
diagonal and every row and column sum at most 4. A mixed-integer linear program
selects the topology and routing for the supplied traffic matrix.
Changing the matrix can change the optimal topology.

The model chooses the topology and routing jointly. Binary variables select
unit-capacity links, while continuous flow variables allow traffic to split
across paths. Each source–destination pair has separate flow conservation
constraints, and the common throughput $theta$ scales every demand.

== Formulation

Let $V={0,dots,n-1}$ be the node set,
$A={(i,j) in V times V : i != j}$ the possible links, and
$K={(s,t) in V times V : s != t}$ the demanded pairs, including pairs with zero
demand. Each nonzero demand is a commodity.

- $x_(i j) in {0,1}$ indicates whether directed link $i -> j$ is selected.
- $f^(s t)_(i j) >= 0$ is the flow rate from source $s$ to destination $t$ on that link.
- $theta >= 0$ is the throughput that scales every traffic demand.

The objective is $max theta$, subject to the following constraints.

*In-degree and out-degree constraints.* Each node has $d$ outgoing and $d$ incoming links.

$ sum_(j != i) x_(i j)=d quad (i in V), quad
  sum_(i != j) x_(i j)=d quad (j in V). $

*Capacity constraints.* All source–destination pairs share the capacity of each selected link.

$ sum_((s,t) in K) f^(s t)_(i j) <= x_(i j) quad ((i,j) in A). $

An absent link has zero flow. A selected link has total load at most one.

*Flow conservation constraints.* For every pair $(s,t)$ and node $v$,

$ sum_(j != v) f^(s t)_(v j) - sum_(i != v) f^(s t)_(i v)
  = cases(theta T_(s t) &"if" v=s,
          -theta T_(s t) &"if" v=t,
          0 &"otherwise"). $

The source generates the scaled demand, the destination consumes it, and every
intermediate node forwards the amount it receives. All expressions are linear because $T$ is constant and capacity uses $x$
directly rather than multiplying it by a flow.
With eight nodes, there are 56 possible directed links and 56 source–destination
pairs. The model therefore has 56 binary link variables, $56^2=3136$ continuous
flow variables, and one throughput variable, totaling 3193 variables. Its 520
constraints comprise 16 degree constraints, 56 capacity constraints, and 448
flow conservation constraints. The uniform case adds the upper bound from
Section 2.

== Correctness of the formulation

Any permitted topology and routing give a feasible model solution by setting
their link variables to 1 and summing each pair's path rates on each link. The degree, capacity,
and flow conservation constraints hold. Conversely, the binary variables of a feasible solution
specify a permitted topology. For each pair, remove any flow cycles and decompose
the remaining flow into source–destination paths. Conservation gives total path
rate $theta T_(s t)$, and shared capacity bounds their combined loads. Removing
cycles only frees capacity. Thus the model and the network problem have the
same feasible throughput values and the same optimum.

A source with row sum $r>0$ gives $theta <= d/r$. A row sum of $d$ therefore
implies $theta <= 1$, whereas smaller demands can permit $theta > 1$. If all demands are zero, every
throughput value is feasible and the objective is unbounded. The implementation records
that status, zero carried traffic, and a valid regular graph.

== Worked example

Set $T_(0 4)=4$ and every other entry to zero. Row 0 and column 4 sum to 4, while
all other row and column sums are zero. Thus the matrix satisfies the row and column bounds. Use the same two-group topology as the uniform eight-node example.
Its node groups are $L={0,1,2,3}$ and $R={4,5,6,7}$, with both directed links
between every cross-group pair. Each node has four incoming and four outgoing links,
including nodes that generate no traffic of their own.

At $theta=1$, send one unit along each of the following paths.

```text
0 -> 4
0 -> 5 -> 1 -> 4
0 -> 6 -> 2 -> 4
0 -> 7 -> 3 -> 4
```

Each path carries one unit, so node 0 sends four units and node 4 receives four.
Every intermediate node forwards the flow it receives. At node 5, outgoing minus
incoming flow is $1-1=0$.

The paths share no directed links, so every used link has load one. Ten selected
links carry traffic, and the remaining 22 carry none.

Any allowed topology gives node 0 only four outgoing units of capacity.
Conservation at the source requires outgoing minus incoming to equal
$4 theta$, so

$ 4 theta <= 4 quad => quad theta <= 1. $

The routing attains this bound, proving global optimality. The unrestricted MILP independently returns
#number(results.single_pair_8.throughput). It may select a different optimal graph.

The total flow delivered is four units, while the sum of link loads is
$1+3+3+3=10$. A flow contributes to the link load at every hop. If the same
matrix instead requests two units, the four-unit routing remains feasible at
$theta=2$, and the cut bound proves that throughput optimal. Throughput above one means
that flow exceeds the requested demand. It does not increase link capacity.

#figure(image("results/topologies.pdf", width: 85%), caption: [Optimal five-node cycle for uniform traffic (left) and four unit-rate paths for the single-pair example (right). Only ten used links are shown on the right. The full topology contains 32 directed links.])

#block(breakable: false)[
= Results

#table(
  columns: (2.6fr, 0.6fr, 0.6fr, 1fr, 1fr),
  align: (left, right, right, right, right), inset: 5pt, stroke: none,
  table.hline(),
  table.header([Traffic matrix], [$n$], [$d$], [Throughput], [Upper bound]),
  table.hline(stroke: 0.5pt),
  [Uniform (cycle construction)], [5], [2], [#number(results.uniform_5.throughput)], [#number(results.uniform_5.global_upper_bound)],
  [Uniform (general MILP)], [7], [2], [#number(results.uniform_7.throughput)], [#number(results.uniform_7.best_bound)],
  [Uniform (MILP)], [8], [4], [#number(results.uniform_8.throughput)], [#number(results.uniform_8.best_bound)],
  [Single-pair (MILP)], [8], [4], [#number(results.single_pair_8.throughput)], [#number(results.single_pair_8.best_bound)],
  [Cyclic (MILP)], [8], [4], [#number(results.cyclic_8.throughput)], [#number(results.cyclic_8.best_bound)],
  table.hline(),
)
]

For $n=7,d=2$, the MILP gives throughput approximately
#number(results.uniform_7.throughput), below the hop-count bound $U(7,2)=0.6$.
Thus the bound need not be attainable, and the explicit constructions do not
cover every parameter choice.

For cyclic traffic with $T_(i, (i+1) mod 8)=4$ and all other entries zero,
every row and column sums to four. The illustrated bipartite topology achieves
throughput #number(results.cyclic_8_bipartite.throughput). In this fixed
topology, the cut $S={0,2,4,6}$ has eight outgoing links and requested
crossing rate $16 theta$, giving $theta <= 0.5$. Optimizing the topology
increases throughput to approximately #number(results.cyclic_8.throughput), with a
matching solver upper bound. Thus a topology optimal for the preceding examples
can be suboptimal for a different traffic matrix.

Gurobi #results.single_pair_8.gurobi_version produced throughputs that agree with
the solver upper bounds to the precision shown. For the cases with explicit
constructions, they also agree with the analytical optima. Recomputed
node degrees, link loads, and source–destination flow balances satisfy the
constraints within $10^(-7)$.

For the maximization MILP, a feasible design gives a lower bound, while the
solver's best bound gives an upper bound on the optimal throughput. These bounds
agree within numerical tolerances for the reported instances. The independent
path-flow LP checks routing on the selected topology, rather than optimality
over all topologies.

Independently formulated path-flow LPs reproduced the fixed-topology optima.
Exhaustive checks on small graphs also agreed with the MILP results.

== Code

The implementation is at #link(repo)[kovaceviccz/cs422-assignment-4].

The functions
#link(repo + "/blob/main/assignment4.py#L37")[`uniform_matrix`] and
#link(repo + "/blob/main/assignment4.py#L128")[`construct_uniform`]
implement the uniform matrix and construction. The function
#link(repo + "/blob/main/assignment4.py#L44")[`solve`]
implements the link variables, source–destination flows, and constraints above. The function
#link(repo + "/blob/main/assignment4.py#L160")[`check_solution`]
recomputes degrees, capacities, and balances from the returned values.
From the repository directory, `python assignment4.py` regenerates the five
examples, figure, and report.

== AI acknowledgment

I used ChatGPT and Codex to discuss the formulations and routing arguments,
develop and check the Gurobi implementation, and edit the report. I questioned
their suggestions and chose which changes to retain.

= Conclusion

The uniform examples show that enough capacity for each node's own demand does
not guarantee throughput one. Forwarding consumes capacity at every hop, and
the routing must distribute that load across the available links. The cycle
and two-group constructions attain matching upper bounds for their stated
parameter ranges.

The MILP extends the optimization to general uniform parameters and arbitrary
traffic matrices by selecting the topology and routing jointly. The explicit
constructions and single-pair example have matching routing and capacity
arguments. The remaining numerical results are checked against the MILP's
upper bounds.
