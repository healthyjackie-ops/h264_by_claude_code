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

## Wave 7 — 多参考

| Phase | 内容 | 验收 |
|---|---|---|
| **15** ✅ | 多参考 P（--ref ≤8）：DPB 滑窗（最新在前 = list0 初始化序、IDR 清空）、ref_idx 语法（CAVLC te(v) / CABAC ctx54+condA+2condB→58→59）、P MB 语法序（全部 ref 先于全部 mvd，分区 ref 预写供 ctxInc）、MV 预测真实 ref 匹配 | 10/10 phase15（振荡运动 + 生成器断言 ref>0 ≥10%，实测 35-96%）；全语料 145/145 |

## Wave 8 — 加权预测 + high P

| Phase | 内容 | 验收 |
|---|---|---|
| **16** ✅ | 显式加权预测（pred_weight_table 解析 + 8.4.2.3.2 单向加权应用于 MC 输出，per-ref luma/chroma w/o）；high profile P 的 inter 8x8 变换（transform_size_8x8_flag 条件 = 分区全 ≥8x8 且 cbp_luma≠0，CAVLC interleave / CABAC cat5，dequant 走 w8[1] inter 列表） | 10/10 phase16（渐隐序列断言 weighted Y >0%，实测全 100%）；全语料 155/155 |

## Wave 9 — B 帧

| Phase | 内容 | 验收 |
|---|---|---|
| **17a** ✅ | POC（8.2.1.1 MSB 滚动/IDR 重置）、输出按 POC 重排、DPB 带运动场 + POC、B slice header、list0/list1 按 POC 分组（8.2.4.2） | 155/155 恒等回归 |
| **17b** ✅ | B MB 层：B/sub mb_type 全表（双熵，CABAC ctx27-32/36-39、intra 后缀 base32）、双向 MC 平均、spatial direct（min-ref/colZero corner/directZero，inference=1）、B_Skip（ctx24）、deblock bS 改 POC 集合比较（双预测两种配对） | 14/14 phase17；全语料 169/169 |

范围钉：--b-pyramid none、--direct spatial（temporal 拒）、--no-weightb。

教训：(1) B 的 cabac_init 也要选 PB 表（只判 is_p 漏了 B → 首 decision 状态错）；
(2) 16x8/8x16/B_8x8 的 L1-only 分区在 list0 mvd pass 不写运动 → 第二分区
的 list1 预测把它当"未解码"——跳过分支必须落定哨兵（mb_ref -2 → -1）。

## Wave 10 — x264 默认参数全覆盖

| Phase | 内容 | 验收 |
|---|---|---|
| **18** ✅ | implicit weighted bipred（dsf=(tb·tx+32)>>8、w0=64-dsf、对称短路）、b-pyramid（参考 B 进 DPB——POC 真排序列表）、ref_pic_list_modification l0（weightp 2 duplicate refs）、MMCO 1、声称 ref 数 > 实际时复制填充 | 10/10 phase18（x264 无任何兼容参数）；全语料 179/179 |

Phase 18 修复的真 bug：(1) B/P 列表构建靠 DPB 扫描序冒充 POC 序——
b-pyramid 下解码序≠POC 序，必须真排序；(2) CAVLC skip_run 是 slice 最后
语法元素时 more_rbsp 提前 false——出口须带 pending skip 守卫；(3) ref_idx
CABAC 是纯 unary（0 终止），按 num_ref 截断会在值=max 时少读 1 bin；
(4) B 两分区 ref 循环未预写网格 → 第二分区 ctxInc 失明；(5) B 的
cabac_init 漏选 PB 表；(6) colocated L0 无效需 L1 fallback。

**已闭环**（曾开放）：p18_fade ±1 根因 = deblock bS 的"非零系数"判定
粒度——8.7.2.1 作用于**变换块**：8x8 变换 MB 中块内任一系数非零则
4 个 4x4 全算 nz（ffmpeg 对 8x8DCT 用 cbp 位特判）。CAVLC interleave
写真实 per-4x4 tc（nC 推导需要）导致部分子块漏判 bS=2。修复：deblock
前对 t8 MB 把 nz 提升到 8x8 块级（nC 已消费完真值，时机安全）。
排障教训：差异帧是非参考 B（poc8）而非 P——按显示序号猜帧类型走了
弯路；JM 文本 trace 的 @ 位与 bits 字段不可信（与真值冲突），python
直读位流仲裁才定案。

## Wave 11 — temporal direct

| Phase | 内容 | 验收 |
|---|---|---|
| **19** ✅ | temporal direct（8.4.1.2.3）：colocated mv 按 POC 距离缩放（tx=(16384+\|td/2\|)/td、DSF=(tb·tx+32)>>6 clip ±1024、mvL0=(DSF·mvCol+128)>>8、mvL1=mvL0−mvCol、等距直拷）、col ref→当前 list0 映射（dpb_ent 存解码时 ref2poc 表）、intra colocated → ref0/mv0 | 14/14 phase19（含 B-pyramid 的 Bref colocated）；全语料 193/193 |
| 加权预测 | pred_weight_table |
## Wave 12 — 鲁棒性

| Phase | 内容 | 验收 |
|---|---|---|
| **20** ✅ | ASan+UBSan 构建（make asan）+ 变异 fuzz（make fuzz：位翻转/截断/替换/重复 ×40/种子）；修 4 处 dequant 负值左移 UB（改 ×2^n 乘法） | 7960 变异零 crash/零 sanitizer/全干净收拒 |

ASO 放弃：x264 不产 ASO 流，无验证手段（做了即死代码）。

## Wave 13 — RTL（进行中）

| Phase | 内容 | 验收 |
|---|---|---|
| **R0** ✅ | RTL 规格冻结（docs/rtl_spec.md）：baseline I 帧 CAVLC 子集、MB 级三段流水（cavlc→recon→deblock）、行缓冲、四层中间值对拍验证策略 | — |
| **R1a** ✅ | bitreader.sv（64-bit 左对齐缓冲/24-bit lookahead/同拍消费+填充）+ expgolomb.sv（组合 ue/se，CLZ≤11） | Verilator 200×600 随机 op 对拍 C bitstream |
| **R1b** ✅ | gen_cavlc_rom.py（C 表→casez SVH，roundtrip 自检，单一可信源）+ cavlc_block.sv（clause 9.2 全 FSM：token/t1/level prefix-suffix 自适应/total_zeros/run_before/置位）+ C 端重放 log（H264_CAVLC_LOG） | **74978 块 bit-exact**（phase05/06/13 全 CAVLC 残差，I+P、escape level、chroma DC/AC） |
| **R1c** ✅ | mb_dec.sv（MB 层 FSM：mb_type/I16 推导/i4 模式预测 min(A,B) 行缓冲/cmode/intra CBP ROM/qp 链/残差序列调度 + nC 行缓冲）+ mb_top 集成（bitreader 双消费者仲裁）| **40/40 向量逐 MB 840B 记录 bit-exact**（phase05+06 全 baseline I）|
| **R2a** ✅ | transform_dec.sv（dequant4x4/luma DC Hadamard/chroma DC/idct4x4_add 组合） | 20000×4 路径随机对拍 bit-exact |
| **R2b** ✅ | intra4x4_pred.sv（9 模式含 z≤−2 角替换）+ intra16_pred/chroma_pred（V/H/DC/Plane、chroma 象限 DC 规则） | 40000+20000 trials bit-exact |
| **R2c** ✅ | mb_recon.sv（MB 重建 FSM：I16 luma DC→预测→16 AC / I4 逐块预测-重建反馈环 / chroma 象限预测+DC+AC、邻样本行缓冲 + TL 角寄存链、chroma QP LUT）+ C 端重建层 dump（H264_RTL_DUMP_REC 384B/MB） | **40/40 向量逐 MB 像素 bit-exact**（phase05+06） |
| R2 | dequant/idct + intra_pred + recon | 重建块对拍 |
| **R3a** ✅ | deblock_edge.sv（强/弱滤波线核 + α/β/tc0 表自动生成）+ C filter_edge 测试出口 | 200000 随机线 bit-exact |
| **R3b** ✅ | deblock_frame.sv（C 同构帧缓冲架构、逐线滤波 FSM、跨 MB QP 平均）+ mb_dec rec_done 握手 + **h264_top 全链集成** | deblock 帧级 14/14；**全链 .264→yuv 38/38 bit-exact**（make top-regress） |
| R3c | 流式行缓冲重构 + ASAP7 综合 PPA | 主频/面积报告 |
| P 帧 | 运动补偿（半/四像素插值）+ ref list + skip |
| RTL | C model 收敛后按 jpeg Wave 节奏移植 |
