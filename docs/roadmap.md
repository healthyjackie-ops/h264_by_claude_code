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

## Wave 2+（暂列）

| 项 | 备注 |
|---|---|
| CABAC I 帧 | 上下文模型 + 算术解码核（可参照 jpeg Phase 21 Q-coder 方法论） |
| High profile | Intra_8x8 + 8x8 变换 + scaling list |
| 多 slice / ASO | 邻块可用性按 slice 边界收紧 |
| P 帧 | 运动补偿（半/四像素插值）+ ref list + skip |
| RTL | C model 收敛后按 jpeg Wave 节奏移植 |
