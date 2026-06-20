# ANN Algorithms in Faiss — Overview

Faiss is not a single ANN algorithm — it is a toolkit of many, composable through
an `index_factory`. ANN methods fall into two complementary categories that are
often combined:

1. **Graph-based indexing** — build a navigable graph so search is a greedy
   traversal (sub-linear, high recall). → HNSW, NSG, NNDescent.
2. **Quantization / compression** — compress vectors into compact codes so
   distances are computed in the compressed domain, scaling to billions of
   vectors in RAM. → PQ, SQ, additive quantizers, RaBitQ, LSH.

The inverted-file (**IVF**) structure provides the coarse partitioning that ties
many of these together.

---

## 1. Graph-based algorithms

### HNSW — Hierarchical Navigable Small World
`faiss/IndexHNSW.h`, `faiss/impl/HNSW.{h,cpp}`

Flagship graph index. Builds a multi-layer graph; upper layers are sparse
"express lanes," layer 0 holds everything. Search greedily descends from an entry
point.

Key parameters (`HNSW` struct, `HNSW.h:59`):

| Param            | Default | Meaning |
|------------------|---------|---------|
| `M`              | 32      | Links per node (`2*M` on level 0, `M` above) |
| `efConstruction` | 40      | Candidate-list size during build |
| `efSearch`       | 16      | Candidate-list size at query (main recall/speed knob) |

State: `entry_point`, `max_level`, per-node `levels`.
Core routines: `greedy_update_nearest` (descend upper layers),
`search_from_candidates` (best-first beam search), `add_links_starting_from`
(insertion).
Variants: `IndexHNSWFlat`, `IndexHNSWPQ`, `IndexHNSWSQ`, plus a Panorama-pruned
search path.

### NSG — Navigating Spreading-out Graph
`faiss/IndexNSG.h`, `faiss/impl/NSG.{h,cpp}`

A flat (single-layer) monotonic graph built **from a kNN graph**. More
memory-compact than HNSW with competitive search.
- `R = 32` — neighbors per node (out-degree)
- `L` — search-path length at construction; `search_L = 16` at query time
- Single `enterpoint`; graph stored in `final_graph`
- `build()` consumes a precomputed kNN graph (from NNDescent or brute force)

### NNDescent
`faiss/IndexNNDescent.h`, `faiss/impl/NNDescent.{h,cpp}`

Algorithm to **construct an approximate kNN graph** cheaply (used standalone and
as input to NSG). Iteratively refines neighbor lists via "local join."
- `K` — graph degree; `S = 10` sampled neighbors/node/iter; `R = 100`
  reverse-link budget; `iter = 10` refinement iterations
- Core loop: `update()` (sample) → `join()` (local join refinement)

---

## 2. Quantization / compression methods

Produce compact codes; search is approximate because distances are computed on
the codes.

- **PQ — Product Quantization** (`IndexPQ.h`, `impl/ProductQuantizer.*`): splits
  the vector into sub-vectors, each quantized by its own codebook. Includes
  **Polysemous codes** (`impl/PolysemousTraining.*`) for fast Hamming
  pre-filtering.
- **Scalar Quantizer** (`IndexScalarQuantizer.h`, `impl/scalar_quantizer/`):
  per-dimension quantization (8/6/4-bit, fp16, etc.).
- **Additive Quantizers** (`impl/ResidualQuantizer.*`, `LocalSearchQuantizer.*`,
  `ProductAdditiveQuantizer.*`): more accurate than PQ — Residual Quantization
  (RQ), Local Search Quantization (LSQ). Exposed via `IndexAdditiveQuantizer.h`.
- **RaBitQ** (`IndexRaBitQ.h`, `impl/RaBitQuantizer.*`): randomized-bit
  quantization, including a multi-bit variant.
- **LSH** (`IndexLSH.h`): classic locality-sensitive hashing baseline.
- **Lattice quantizer** (`IndexLattice.h`, `impl/lattice_Zn.*`).

---

## 3. IVF — the coarse partitioner that scales everything

`faiss/IndexIVF.h` and subclasses are the workhorse for large-scale ANN. A coarse
quantizer (k-means centroids, or even an HNSW quantizer) partitions space into
`nlist` cells; at query time only `nprobe` nearest cells are scanned.

Combines with every compression scheme:
- `IndexIVFFlat` — IVF + raw vectors
- `IndexIVFPQ`, `IndexIVFPQR`, `IndexIVFPQFastScan` — IVF + PQ (+ refine, + SIMD fast-scan)
- `IndexIVFScalarQuantizer`, `IndexIVFAdditiveQuantizer`, `IndexIVFRaBitQ`, `IndexIVFSpectralHash`

**FastScan** (`impl/fast_scan/`, `pq_code_distance/`): SIMD-vectorized in-register
lookup tables for 4-bit PQ codes — large speedups.

---

## 4. Supporting / refinement pieces

- **IndexRefine** (`IndexRefine.h`): two-stage — fast approximate shortlist, then
  re-rank with a more precise index.
- **Exact baselines** (`IndexFlat.h`): brute-force L2/IP, the recall reference.
- **Binary indexes** (`IndexBinary*`): Hamming-space ANN, incl. `IndexBinaryHNSW`,
  `IndexBinaryIVF`.
- **Panorama** (`impl/Panorama.*`): progressive-pruning scan optimization (wired
  into HNSW and IVFFlat in this branch — see `IndexIVFFlatPanorama.h`).
- **Clustering** (`Clustering.h`, `kmeans1d`): k-means used to train coarse
  quantizers.

---

## How it all composes

The `index_factory` (`faiss/index_factory.h`) builds these from strings:

| Factory string                 | Result |
|--------------------------------|--------|
| `HNSW32`                       | HNSW graph, M=32 |
| `IVF4096,PQ16`                 | IVF with 4096 cells, 16-byte PQ codes |
| `IVF65536_HNSW32,PQ32`         | HNSW-quantized IVF + PQ |
| `OPQ16_64,IVF4096,PQ16`        | OPQ pre-rotation (`VectorTransform.h`) + IVF-PQ |

**In short:** the "ANN algo" in this repo is a construction kit — graph traversal
(HNSW/NSG) for in-memory high-recall search, and IVF + quantization
(PQ/SQ/AQ/RaBitQ) for billion-scale compressed search — frequently stacked
together.
