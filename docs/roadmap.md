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

## Wave 3 — High profile I 帧（完成）

| Phase | 内容 | 验收 |
|---|---|---|
| **10** ✅ | Intra_8x8（9 模式 + 8.3.2.2.1 参考样本滤波）+ 8x8 变换/反量化 + transform_size_8x8_flag（CAVLC u1 / CABAC ctx399+inc）+ CAVLC 4x4 交错 + CABAC cat5（sig/last 8x8 位置映射、无 cbf）+ second_chroma_qp_offset（Cr 独立 QPc，含 deblock）+ deblock 8x8 内部边跳过 | 18/18 phase10 向量 bit-exact（CABAC+CAVLC，平均 8x8 占比 45%、最高 100%）；全语料 78/78；errtest 6/6 |

## Wave 4 — scaling list + 多 slice

| Phase | 内容 | 验收 |
|---|---|---|
| **11** ✅ | scaling list：SPS/PPS scaling_list() 解析（delta_scale 链 + useDefault）、默认矩阵 Table 7-3/7-4、fall-back 规则 A/B（B 仅当 SPS 实际带矩阵）、dequant 全家族接 weightScale（4x4/8x8/luma DC/chroma DC per-list）| 14/14 phase11（jvt fall-back + cqmfile 显式链 × CABAC/CAVLC × 8x8 on/off）；全语料 92/92 |
| **12** ✅ | 多 slice I 帧：slice 收集 + per-slice 解码状态（CABAC 重 init/qp 链）、邻块可用性按 slice 边界（mb_avail/blk4_avail 统一 6.4.9 语义，覆盖 intra pred/nC/全部 ctxInc/cbf/TR）、per-MB deblock 参数（idc==1 整 MB 禁滤、idc==2 跨 slice 边不滤、offset 随 q 侧 MB） | 14/14 phase12（2..8 slices × main/high × CABAC/CAVLC）；全语料 106/106 |

Phase 11 教训：(1) x264 --cqm 写 PPS 不写 SPS；(2) fall-back rule B 仅在
SPS 真带矩阵时继承，matrix-less SPS → rule A 默认；(3) chroma DC 反量化
无舍入项（JM 插桩验证 `((f·w0·V0)<<p)>>5`），luma DC/4x4/8x8 才带
rshift_rnd_sf 舍入。

## Wave 5 — P 帧（CAVLC 完成）

| Phase | 内容 | 验收 |
|---|---|---|
| **13a** ✅ | 多帧解码架构（nframes API + picture 循环 + golden 多帧比对） | 3×IDR 序列 bit-exact |
| **13b** ✅ | P 帧 CAVLC：6-tap qpel luma MC + 1/8 双线性 chroma、P_L0 全分区（16x16/16x8/8x16/8x8+子分区）、MV 中值预测（16x8/8x16 方向特例 + only-A 规则）、P_Skip（零强制条件）、mb_skip_run、inter CBP me 表、P slice 内 intra MB、inter deblock bS 0/1/2（per 4-样本段，nz/ref/mv 差推导） | 14/14 phase13（运动/场景切换/非对齐/deblock on/off）；全语料 120/120 |

教训：(1) intra MB 的运动哨兵（-2）必须在 mb_done 归位为 -1，否则邻居
MV 预测把 intra 邻当"未解码"；(2) `a || b && c` 的 shell 优先级吞掉了
patch 应用，叠加 python replace 无断言 → 二分时状态错乱——一切 replace
必须 assert；(3) 参考帧是**全 MB 网格**（crop 只影响输出），MC clamp 用
padded 尺寸。

## Wave 6 — P 帧 CABAC

| Phase | 内容 | 验收 |
|---|---|---|
| **14** ✅ | P CABAC：mb_skip_flag ctx11+邻、P mb_type 树 ctx14-17（intra 后缀 base17 平铺 ctx）、sub_mb_type ctx21-23、mvd UEG3 ctx40/47（邻 \|mvd\| clip70 ctxInc、TU≤9 + EG3 bypass）、PB 上下文初始化表 ×3（cabac_init_idc slice 字段）、cbf inter 邻规则（不可用→cur_intra）、CBP/qp_delta/残差复用 | 15/15 phase14（main P 全矩阵 + 多 slice）；全语料 135/135 |

教训：x264 main/high 默认 --bframes 3 / --weightp 2——P 向量必须显式
--bframes 0 --weightp 0，否则混入 B slice/加权预测被正确拒掉、但向量
就测不到目标路径（与"覆盖率要可证"同一课）。

## Wave 7+（暂列）

| 项 | 备注 |
|---|---|
| 多参考 / B 帧 | ref_idx 语法 + list1 + POC 重排 |
| 加权预测 | pred_weight_table |
| ASO | first_mb 乱序（mb_avail 已就绪，解析序需重排） |
| RTL | I 帧子集起步 |
| P 帧 | 运动补偿（半/四像素插值）+ ref list + skip |
| RTL | C model 收敛后按 jpeg Wave 节奏移植 |
