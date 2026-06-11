# H.264 RTL 规格冻结（Phase R0）

C 模型已完备（193/193 bit-exact vs ffmpeg + fuzz 干净），RTL 化开始。
路线复用 jpeg_by_claude_code 的已验证方法：子集冻结 → 逐模块 RTL +
C 模型黄金中间值对拍 → Verilator 帧级 bit-exact → ASAP7 综合 PPA。

## 子集范围（R1 目标，冻结）

| 项 | 范围 | 理由 |
|---|---|---|
| Profile | Baseline I 帧 | 无帧间/无 CABAC，最小可流片子集 |
| 熵编码 | CAVLC only | CABAC 的 bin 级串行反馈环是独立大课题，二期 |
| 分辨率 | ≤ 1080p（mb_w ≤ 120） | 行缓冲尺寸上限 |
| 输入 | 预解析 slice RBSP（SPS/PPS 字段经寄存器接口下发） | NAL/参数集解析留软件，RTL 专注数据通路 |
| 输出 | yuv420p 原始帧，MB 行粒度回写 | |
| Deblock | 含（I 帧 bS=4/3 简化路径） | 输出 bit-exact 必需 |

明确不做（一期）：CABAC、P/B 帧、8x8 变换、scaling list（flat 16 固化）、
多 slice、I_PCM（解析支持但走 bypass 通路）。

## 顶层架构

```
                 ┌─────────────────────────────────────────────┐
 reg if ────────►│ cfg（SPS/PPS 字段：尺寸/qp/crop/deblock 参数）│
                 └─────────────────────────────────────────────┘
 rbsp stream ──► bitreader ──► cavlc_dec ──► coef_buf ──► dequant/idct ─┐
 (8b/cyc)        (ue/se/u(n))  (coeff_token   (16x16+2x8x8   (4x4 蝶形)  │
                               /tz/run 表)     系数/MB)                  ▼
                                                            ┌── recon ──┐
                 nbr_line（上邻行缓冲：重建样本+nz+模式） ◄──┤ intra_pred │
                                                            └─────┬─────┘
                                                                  ▼
                                                          deblock（MB 滞后一拍）
                                                                  ▼
                                                            wb（MB 行 FIFO → 外存）
```

- **MB 级流水**：cavlc 解第 N 个 MB 时，recon 在 N-1，deblock 在 N-2。
  JPEG 项目同构（huffman/drain/upsample 三段），复用其握手协议
  （valid/ready + MB 边界 token）。
- **行缓冲**：上邻重建样本（mb_w×16 luma + 2×mb_w×8 chroma）、
  上邻 nz（nC 推导）、上邻 i4 模式。单口 SRAM，MB 串行访问。
- **intra 依赖环**：4x4 模式下块间串行（左邻重建反馈），与 JPEG 的
  DC 预测环同性质——recon 子级按 4x4 z 序串行，目标 ≥1 像素/周期。

## 验证策略（冻结）

1. **C 模型黄金中间值**：c_model 加 `H264_RTL_DUMP=路径`，逐 MB 输出
   {系数(zigzag 后)、预测块、重建块、deblock 后}四层中间值——RTL 各级
   testbench 直接对拍（JPEG 的 phaseN 中间值法）。
2. **向量复用**：phase04/05 的 baseline CAVLC I 帧向量即 RTL 回归集；
   x264 --profile baseline --keyint 1 补充多帧。
3. **帧级**：Verilator 全链 testbench，输出 yuv 与 c_model bit 级 cmp。
4. **综合**：ASAP7，目标主频/面积在 R3 评估（JPEG 同流程）。

## Phase 划分

| Phase | 内容 | 验收 |
|---|---|---|
| R0 ✅ | 本规格冻结 | — |
| R1 | c_model 中间值 dump 接口 + bitreader + cavlc_dec | 逐 MB 系数对拍全过 |
| R2 | dequant/idct + intra_pred + recon | 重建块对拍 |
| R3 | deblock + wb + 帧级集成 | 帧 bit-exact；ASAP7 综合 |
