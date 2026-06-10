# Roadmap

流程模板来自 jpeg_by_claude_code：每 phase 一个 commit，验收 = 本 phase 向量
bit-exact + `make regress` 全量零退步 + `-Werror` 干净构建。

## Wave 1 — I 帧 CAVLC（C model）

| Phase | 内容 | 验收 |
|---|---|---|
| **00** ✅ | Spec 冻结 + 骨架 + roadmap | docs 合入 |
| **01** ✅ | bitstream（RBSP u/ue/se）+ NAL（Annex-B + EPB） | test_bitstream 单测全过 |
| **02** ✅ | SPS / PPS / slice header（I/IDR） | 解析字段 == x264 编码参数（64x48 / 100x76 crop 交叉验证） |
| **03** ✅ | CAVLC 残差（coeff_token ×4 表 + total_zeros + run_before + level） | 表转录自 ffmpeg；随 Phase 4/5 golden 验证 |
| **04** ✅ | Intra 预测（4x4/16x16/chroma）+ 反量化 + IDCT + I_PCM + crop | 10 例 ad-hoc 矩阵 bit-exact（DC 反量化 ×16 修正后一次通过） |
| **05** ✅ | no-deblock 向量矩阵（尺寸×qp×图案）golden bit-exact | 22/22 + 真实照片帧 |
| **06** ✅ | deblocking filter（bS/α/β/tc0 + 强弱滤波 + chroma） | 18/18 deblock-ON（含 offset 扫描）；全量 40/40 |
| **07** ✅ | 错误向量 + errtest + 泄漏检查 + README | 6/6 拒绝（trunc/no-SPS/garbage/CABAC/多slice/空流），0 泄漏 |

## Wave 2 — CABAC I 帧（完成）

| Phase | 内容 | 验收 |
|---|---|---|
| **08** ✅ | CABAC 引擎（Table 9-44/9-45 + ctx init 0..276）+ 逐 bin JM 对拍 | 引擎 trace 与 JM TRACE=2 完全一致 |
| **09** ✅ | I 帧 CABAC 语法（mb_type/pred/CBP/qp_delta/残差/eos）| 20/20 phase08 向量 bit-exact；全语料 60/60；errtest 6/6 |

关键教训：x264 tables.c 的 range_lps 表按**反向 state 序**存储，
不能直接当规范 Table 9-44 用（JM biaridecod.h 才是规范序）；CBP chroma
的不可用邻语义是 condTerm=0（边界 cbp 视作 0x0F，验 JM 而非凭 ffmpeg
代码记忆）。调试链路：CABAC_DBG=1 引擎 trace ↔ JM ldecod TRACE=2。

## Wave 3+（暂列）

| 项 | 备注 |
|---|---|
| High profile | Intra_8x8 + 8x8 变换 + scaling list |
| 多 slice / ASO | 邻块可用性按 slice 边界收紧 |
| P 帧 | 运动补偿（半/四像素插值）+ ref list + skip |
| RTL | C model 收敛后按 jpeg Wave 节奏移植 |
