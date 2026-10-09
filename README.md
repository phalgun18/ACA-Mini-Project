
# Mini-Project Part 1: The Matrix-Multiply Unit

**CS2.501 Advanced Computer Architecture · Monsoon 2026 · IIIT Hyderabad**

**Name:** Phalgun (MS 1)  **Roll No.:** 2026702011

Three BSV designs of `C[4][4] += A[4][4] × B[4][4]` (Int8 operands, Int32 accumulator): **A** fully combinational, **B** K-serial (one outer product per cycle), **C** K-serial with a second copy of A/B so loads overlap the running Mul. All three pass both workloads with 0 errors.

## 1. Measurements

| Design | W1 cycles | W2 cycles | Stalls (W1 / W2) | Cells | Logic depth |
|---|---:|---:|---:|---:|---:|
| A | 40,961 | 299,009 | 1 / 1 | 113,160 | 71 |
| B | 57,345 | 430,081 | 16,385 / 131,073 | 16,288 | 59 |
| C | 41,729 | 299,777 | 769 / 769 | 29,874 | 61 |

W1 = 64×64×64 (40,960 requests, 262,144 MACs). W2 = 64×512×64 (299,008 requests, 2,097,152 MACs).

| Design | cycles × depth, W1 | cycles × depth, W2 | cells × depth | MACs / request (W1 / W2) |
|---|---:|---:|---:|---:|
| A | 2,908,231 | 21,229,639 | 8,034,360 | 6.40 / 7.01 |
| B | 3,383,355 | 25,374,779 | **960,992** | 6.40 / 7.01 |
| C | **2,545,469** | **18,286,397** | 1,822,314 | 6.40 / 7.01 |

Rankings change by column: fewest cycles is A (C is only 1.9% behind on W1), best time (cycles × depth) is **C**, smallest hardware and best cells × depth is **B**. `logic_depth` is a proxy for clock period, not nanoseconds.

## 2. Predictions and where they were wrong

| Item | Predicted | Measured | Why it differed |
|---|---|---|---|
| A, cycles/tile | 9 | 9 (+16 reads per output tile) | Held. |
| B, cycles/tile | 8 + ℓ = 12 | 13 (4 stalls per Mul) | The Mul request is accepted in its own cycle, and the ℓ = 4 slices run *after* it, so the cost is 9 + ℓ. |
| C, cycles/tile | 9, only the 1 end stall | 9, but 769 stalls | Loads never stall, but ReadC must wait for the last Mul of each output tile to finish: 3 cycles × 256 tiles + 1. |
| Cells | B < C < A | B < C < A | Ranking held, but C is +13.6k cells over B, far more than the 512 extra flops explain. |
| Logic depth | B < C < A | B (59) < C (61) < A (71) | Ranking held, but the size was a surprise: 4× fewer multipliers cut depth only 17%. |

For B and C the workload formulas are: cycles = 256 × (K-tiles × tile cycles + 16 + wait) + 1. For example, B on W1: 256 × (16×13 + 16) + 1 = 57,345.

## 3. Answers to §10

**Did the prediction hold?** Cycles: yes, once the accept cycle and the ReadC wait were counted (table above). Both formulas reproduce all six measured cycle counts exactly.

**Where do the cycles go?** A: 1 stall (the last response lands one cycle after the last request). B: 4 stalls per Mul (16,384 + 1 on W1), because every request waits while the Mul runs. C: 3 stalls per output tile (768 + 1), only ReadC waiting for the final Mul.

**Why is MACs/request identical for all three?** It is set by the interface, not the hardware: a tile is 8 loads + 1 Mul + 16 reads shared across the K-tiles, and each request carries one 32-bit word, so every design sees the same requests for the same MACs (262,144 / 40,960 = 6.40; 2,097,152 / 299,008 = 7.01). Inside the unit only changes *when* requests are accepted. To move it, a request must carry more per instruction, for example descriptor/DMA loads of whole tiles (Appendix A: 9 requests per tile become 3), or a larger tile.

**What sets the longest path?** One output is one multiply followed by a sum over K (plus the old C). The multiply dominates: going from A to B removes 3 of the 4 stages of the K-sum and 48 of 64 multipliers, yet depth only falls 71 → 59 (about 12 levels), and B adds a 4:1 mux on the slice index. So "fewer multipliers" (cells down about 7×) and "shorter critical path" (depth down 17%) are different properties. Part of the A→B cell drop also comes from B/C using `signedMul` (8×8 → 16 bit) rather than 32-bit multipliers; I did not separate the two effects. C is 2 levels deeper than B with the same multiplier array, probably from the extra copy and more writers on `rg_c`; I did not verify this.

**LoadA during a Mul (B and C).** §3 says responses must equal a one-request-at-a-time unit. In B, the Mul reads all of A and B on every slice, and a LoadA rewrites a whole row (all four columns), so it would change later slices. B therefore holds *every* request (loads, ReadC, next Mul) while busy; this costs ℓ cycles per Mul. C copies A and B into a working copy when the Mul is accepted, so loads proceed freely into the load copy. C still holds the next Mul (one engine, one C) and ReadC (C is half-accumulated). Cost: 512 more flops, and ℓ−1 cycles per output tile instead of ℓ per Mul.

**W1 vs W2.** Both have 4,096 reads, but W1 averages 10.0 cycles per read and W2 73.0, so W2 costs more per unit of readout (it does 8× more work between readouts). Per MAC it is cheaper because readout is amortised (10% of requests in W1, 1.4% in W2):

| Cycles per MAC | A | B | C |
|---|---:|---:|---:|
| W1 | 0.1563 | 0.2188 | 0.1592 |
| W2 | 0.1426 | 0.2051 | 0.1430 |
| Drop | 8.8% | 6.2% | 10.2% |

C is the most sensitive to the workload: its only overhead is per output tile (readout + 3-cycle wait), which deeper accumulation amortises. B is the least, because its 4 stalls recur on every Mul, so they never amortise.

**Accumulator width.** A product is at most 2^(2·W_ELEM − 2) in magnitude (−128 × −128 = 2^14). With K products per Mul and N Muls between readouts, |C| ≤ N·K·2^(2·W_ELEM − 2), so **W_ACC ≥ 2·W_ELEM + ⌈log2(K·N)⌉** (signed). For W_ELEM = 8, K = 4 this is 18 + log2 N, so at W_ACC = 32, N ≤ 2^14 = 16,384 Muls (W2 needs only 128). At W_ACC = 16 the bound gives N·K < 1: even a single Mul (4 × 16,384 = 65,536 > 32,767) can overflow in the worst case, so zero Muls are guaranteed safe. This is why accumulators are wider than operands and why C is read out and zeroed.

**DMA.** For an S×S×S tile, MACs/byte = S/2 and MACs/instruction ≈ 2S. Assuming the array does 64 MACs/cycle at 1 GHz (Appendix A), a 4×4×4 tile (2 MACs/byte) needs 64 / 2 = **32 bytes/cycle = 32 GB/s**, which is already more than one DRAM channel gives. So a DMA-fed 4×4×4 unit is memory-bound as soon as instruction supply stops limiting it (about 3 instructions, or 21 MACs/instruction, per tile). In general the requirement is 128·f / S bytes/s, so, for example, a 16 GB/s budget needs S ≥ 8. One guarantee the OS must provide that §2 does not need: **page pinning** (pages must not move or be swapped out during the transfer). Cache coherence and address translation are the other two.

**`make schedule`.** bsc schedules whole rules, so there is one rule per request type. In B and C, `rl_step`, `rl_mul` and `rl_read_c` all write `rg_c`; they are made mutually exclusive by the `rg_busy` guard rather than by ordering, and in B the loads are guarded by it too.

## 4. Choice

**Chosen: Design C**, under the priority *minimum time to finish the job (cycles × logic depth) at moderate area*. C is best on that measure on both workloads (18.29 M vs 21.23 M for A on W2, 14% lower; 25.37 M for B), while being 3.8× smaller than A. It wins even though A has fewer cycles, because its depth is 10 levels lower.

**Strongest argument against it:** B is 1.9× better on cells × depth (960,992 vs 1,822,314) and has almost half the cells, so under an area-first priority B is the right design. Also, C's advantage is the 4 cycles per Mul it hides, which only matters if the requester issues one request per cycle. In Part 2 a real in-order CPU may not (§12), which would shrink C's cycle gain over B while its area cost stays.


