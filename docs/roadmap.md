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

## Wave 14 — RTL P 帧硬化（进行中）

| Phase | 内容 | 验收 |
|---|---|---|
| **P-R1** ✅ | mc_core.sv（mc4x4_luma 15 qpel 相位 9x9 窗口 + mc4x4_chroma 1/8 双线性 5x5）| 60000 随机 trial（全相位+边缘 clamp）bit-exact vs mc.o，第一发全过 |
| **P-R2** ✅ | mc_fetch.sv：参考帧留系统侧（DDR/pad 帧），核发 clamp 语义窗口行读（req x/y/w → rsp 9px 行）；坐标推导（xInt=px+mv>>2、相位=mv&3）入 RTL；统一 4x4 粒度（分块插值与整块数学等价） | 20000 块（随机 MV 越界+全相位+取数协议）bit-exact，第一发全过 |
| **P-R3a** ✅ | P 语法基建：H264_RTL_DUMP_P（140B/MB：skip/type/sub/mvd 解析序/最终 MV z-scan，gate=CAVLC P+nref1+no-8x8）+ inter CBP ROM（Table 9-4）+ mb_dec/mb_top cfg_is_p 通路 | dump 三 call site 全捕获；I 回归 40/40 不退化 |
| **P-R3b** ✅ | mb_dec P MB 层 FSM：mb_skip_run 链（7.3.4 do/while——run 终结的 coded MB 不再读 skip_run）+ P mb_type（0..4 inter / ≥5 转 I）+ P_8x8(ref0) sub_mb_type + mvd 对流（计数 0→1/1,2→2/3→4）+ inter CBP + inter 残差复用 I 通路（i16=0 路径零增码）；tb_p_parse 差分台 + make p-regress | **24 条 CAVLC baseline P 流逐 MB 语法 bit-exact**（skip/type/sub/mvd 全比对，phase13/15/16/17 含多参考首帧），I 回归 40/40+40/40 |
| **P-R3c** ✅ | mv_pred.sv：中值 MV 预测（8.4.1.3 方向规则/only-A/单匹配/分量中值）+ P_Skip 推导（8.4.1.1）+ 行缓冲邻块状态（底行 + 左列 + TL 角链，intra 条目 inter=0）；复刻 C 的 ref 预写语义（16x8/8x16/P_8x8 预写 → 前向块读 inter mv(0,0)，P_8x8ref0 不预写 → undecoded）；每 mvd 拍单分区计算，commit 拍推进 | **24 条 P 流逐 4x4 块最终 MV bit-exact**（z-scan 场全比对），I 回归 40/40+40/40+38/38 |
| **P-R3d** ✅ | inter 重建集成：mb_recon S_MC 子环（48 块/MB：16 luma 4x4 z 序 + 32 chroma 2x2，双线性逐像素独立故 2x2 取 4x4 插值左上角精确）经 mc_fetch 行读通道（+plane 维度）取预测；inter 残差复用 I 通路（id_pred 改读 rec_*、跳过 intra 预测态）；p_rec_top 差分顶层 + C 端 H264_RTL_DUMP_PREC（384B/MB @mb_done，含 skip MB）/H264_RTL_DUMP_REF（首个门控 P slice 的未裁剪 list0[0] 平面）| **24 条 P 流逐 MB 像素 bit-exact（make prec-regress，第一发全过）**；I 回归 40/40+40/40+38/38、C 193/193 |
| **P-R3e** ✅ | h264_core 完整 I/P 核：cfg_is_p + mv_pred 入核、MC 行读通道出核、参考帧回写闭环（tb 持帧：滤波输出 → 下一帧参考）；**deblock P bS**（8.7.2.1 单参考子集：intra→4/3、nz→2、|Δmv|≥4→1、否则 0 不滤；bS=0 写回门控；chroma 逐 luma 块行映射）——nz/mv/inter sideband 从 mb_dec 经 mb_recon 贯通 deblock_stream（row_mi 133b 行缓冲 + cur/left/top 状态）；全 I 流自然退化为旧 4/3 常数 | **15 条多帧 I/P 流（含 deblock）帧级 yuv bit-exact（make corep-regress）**；全回归 40/40+40/40+38/38+24/24+24/24、C 193/193 |

## Wave 16 — RTL B 帧硬化（进行中，规格 docs/rtl_b_spec.md）

| Phase | 内容 | 验收 |
|---|---|---|
| W16-a | mb_dec CAVLC B 语法 + mv_pred 双 list + spatial direct | B 语法/MV dump 逐 MB bit-exact |
| W16-b | mb_recon 双向 MC + avg + 核集成（list 通道、tb DPB） | phase17 CAVLC B 多帧 yuv bit-exact |
| W16-c | temporal direct（colocated 通道 + POC 缩放） | phase19 CAVLC 流 bit-exact |
| W16-d | CABAC B + 双熵 | phase17/19 全熵 bit-exact |

## Wave 15 — RTL CABAC 硬化（已完成）

| Phase | 内容 | 验收 |
|---|---|---|
| **W15-a** ✅ | cabac_core.sv：9.3.3.2 算术解码引擎（decision/bypass/terminate 单拍/bin、renorm 组合 CLZ 移位 + show 窗口同拍消费、436 ctx flop-RF 同拍读改写、串行 init FSM 436 拍 + 9-bit prime）+ gen_cabac_rom.py（rangeTabLPS/状态转移/4 模型 init 表自 cabac.c 生成,单一可信源） | **833,673 bins bit-exact vs C 引擎**（400 随机流 × 随机 op/ctx 序列,terminate hit 重 init） |
| **W15-b/c** ✅ | cabac_mb.sv：CABAC I slice 完整 MB 层解析器（mb_dec 的 CABAC 孪生,接口全兼容）——mb_type 树（ctx 3..10 + 邻块 inc）/prev+rem intra4x4（68/69 + min 预测）/chroma mode（64..67）/CBP（73..84 邻位规则）/qp_delta（60..63 unary）/逐块 cbf（85+cat*4+cond,规范邻块项含 I16-vs-I4 DC 规则）/sig+last 图（105/166+off+pos）/level 节点机（227+,EG0 bypass 逃逸）/sign bypass/每 MB end_of_slice terminate；邻块状态 = nrow 35b 打包行缓冲（cat/cmode/cbp/ldc/cdc/cbf 底行/i4 底行）+ 左寄存组 | **20 条 CABAC I 向量逐 MB 840B 记录 bit-exact（make cmb-regress），组装后第一发全过**；CAVLC/C 回归零退化 |
| **W15-c2** ✅ | h264_core 熵双路：cabac_mb 与 mb_dec 并列（cfg_cabac 选路,header/coef 流 mux,bitreader 第三请求方,非活动方 start 门控）；CABAC I 流走完整核（重建+deblock）| **core-regress 60/60（40 CAVLC + 20 CABAC I 帧级 yuv bit-exact,第一发全过）**；全回归零退化 |
| **W15-d** ✅ | cabac_mb P 扩展：mb_skip_flag（11+inc 邻 skip 行缓冲）/P mb_type 树（14-17）/intra suffix（base17,ctx 复用模式与 I 树不同）/sub_mb_type（21-23）/UEG3 mvd（40/47+amvd 邻和 inc,unary ctx +3..+6,EG3 逃逸；|mvd| clip70 行缓冲 92b 打包,未写=0 即 calloc 语义）/inter cbf（不可用→0）/cabac_init_idc 模型；h264_core P 流 mux（mv_pred/mb_recon/deblock 共享） | **corep-regress 30/30（15 CAVLC + 15 CABAC P 多帧流帧级 yuv bit-exact,组装后第一发全过）**；全家回归零退化 |

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
| **R3c** ✅ | h264_core 综合顶层（去帧缓冲）+ sv2v→yosys→ASAP7 流程（syn/，复用 JPEG 基建） | **449K cells / 49K FF / 44,680 µm² / Fmax 286 MHz**（docs/synthesis_r3c.md）|

| **R4a** ✅ | dequant/intra→IDCT 一级流水（latch+write 拆拍） | **300 MHz 收敛**（WNS +0.4ps，面积 +0.3%），回归 40/40+38/38 |

**RTL 三阶段（R0-R3c）+ R4a 完成**：baseline-I 硬件解码器全链 .264→yuv
38/38 bit-exact + ASAP7 综合基线。R4 候选：SRAM 化/流水化（300MHz+）、
deblock 流式重构、CAVLC 单拍化——见综合报告下一步。
| P 帧 | 运动补偿（半/四像素插值）+ ref list + skip |
| RTL | C model 收敛后按 jpeg Wave 节奏移植 |
