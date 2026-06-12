# R3c — ASAP7 综合基线报告（串行架构首轮）

**Target**: h264_core（每-MB 解码引擎：bitreader + mb_dec + cavlc_block +
mb_recon；帧缓冲/deblock_frame 属外置存储域，不在本轮综合范围）
**Tool**: Yosys 0.63 + ABC（map+buffer+upsize+dnsize）+ sv2v v0.0.13
**Liberty**: ASAP7 7.5T RVT TT（asap7_merged_RVT_TT.lib，同 JPEG 项目）
**约束**: D = 3333 ps（300 MHz 目标）

## 结果

| 指标 | 值 |
|---|---|
| 映射 cell 数 | 449,550 |
| 触发器 | 49,049 |
| 逻辑面积 | 44,680 µm² |
| 关键路径 | **3491 ps → Fmax ≈ 286 MHz**（距 300 MHz 目标 −158 ps / 4.7%） |
| 未映射存储 | 2 × $mem_v2（行缓冲推断，SRAM 外挂成本，asap7_mem_area.py 流程同 JPEG） |

## 解读

- 串行基线（每 4x4 块的 dequant+IDCT 全组合、intra 预测全组合）一次
  综合就到 286 MHz——关键路径在意料中的 dequant×IDCT×clip-add 组合链。
  300 MHz 收敛只差一档 retiming/一级流水。
- 49K FF 的大头是 mb_recon 的像素/系数寄存阵列（rec_y 2048b + cram
  6912b + 行缓冲 ~20Kb）——下一轮把行缓冲与 cram 显式 SRAM 化可砍掉
  大部分（JPEG 同演进路径）。
- 吞吐（串行）：~2 拍/语法元素 + 重建 ~30 拍/MB。286 MHz 下保守估算
  >100K MB/s，1080p I 帧（8160 MB）约 12 fps——流水化前的基线。

## 复现

```
cd syn && make sv2v && make synth
```
（.lib 不入库：从 jpeg_by_claude_code/syn/asap7/ 拷贝，见 syn/README.md）

## R4a — IDCT 流水级（已完成）

dequant/intra 预测结果在进入 IDCT+clip-add 前打一级寄存
（S_YBLK/S_CBLK 拆 latch+write 两拍），把关键路径从
cram→dequant→IDCT→clip 全组合链切成两半：

| 指标 | R3c 基线 | R4a 流水 |
|---|---|---|
| 关键路径 | 3491 ps（286 MHz） | **3332.6 ps（300 MHz，WNS +0.4 ps）** |
| 面积 | 44,680 µm² | 44,830 µm²（+0.3%） |
| 周期代价 | — | +1 拍/4x4 块（~24 拍/MB） |

回归零退步：mb-regress 40/40、top-regress 38/38。

## R4b — CAVLC 单拍化（已完成）

cavlc_block 的 req 从寄存输出改为组合（Mealy）：FSM 推进与 bitreader
消费同沿，每个语法元素 1 拍（原 2 拍）。两个连带改动：

1. **饥饿 gate**：单拍消费（峰值 ~29 bits/2 拍）可超过 8 bits/拍的
   字节填充——窗口跌穿 24 bits 后右端补零会被解成"假全零码"
   （74978 块重放精确抓到 5 个大 level escape 块在 avail 枯竭点出错）。
   FSM 动作 gate 在 `avail≥24`，testbench 给流尾加 8 字节垫。
2. mb_dec/cavlc 仲裁不变（mb_dec 仍 2 拍/元素，R4 余项）。

| 指标 | R4a | R4b |
|---|---|---|
| 关键路径 | 3332.6 ps（300 MHz） | **3353.6 ps（298 MHz，−0.6%）** |
| 面积 | 44,830 µm² | 44,843 µm² |
| CAVLC 吞吐 | 2 拍/元素 | **1 拍/元素**（高码率流收益显著；低码率流被填充等待抵消） |

代价：coeff_token casez → req_bits → bitreader 填充算术成为新关键路径，
300 MHz 差一档 sizing。回归零退步：74978 块 + 40/40 + 38/38。

## R4c — mb_dec 单拍化（已完成）

R4b 的 Mealy 模式复制到 MB 层（mb_type/i4 模式/cmode/CBP/qp_delta 全
1 拍，同 avail≥24 gate）。第一发全回归绿——验证模式成熟的标志。

| 指标 | R4b | R4c |
|---|---|---|
| 关键路径 | 3353.6 ps | **3352.4 ps（持平，瓶颈仍在 cavlc req 路径）** |
| 面积 | 44,843 µm² | 44,838 µm² |
| 64x64 帧周期 | 4598 | 4566 |
| 48x48 q2 帧周期 | 12728 | 12642 |

头部语法收益被残差块支配（合理）；真正的吞吐余量在输入加宽与
recon 并行化。

## R4d — 存储 SRAM 化（已完成）

行缓冲与系数 RAM 重组为 memory 推断形态：宽字组织（每 MB 列一个字：
top_y 120×128b、cram 27×256b 等）+ 单写口（写整字读改写，chroma nz
按分量拆两数组消除双写口）+ 异步 assign 读口 + MB 入口预取拍 +
cram 串行清零（27 拍，放进 mb_dec 的 stall 窗口消除与下一 MB 系数流
的竞态——全链回归曾精确暴露该竞态：x≥16 的 MB 列全错）。

三个工具链教训：
1. **函数包 memory 读**会被 sv2v 内联成 `always @(cram)` 敏感列表，
   yosys 前端直接拒收（"Insufficient array indices"）→ 改连续 assign。
2. **动态 part-select 写**（`cram[blk][addr*16+:16] <=`）触发 mem2reg
   → 改整字读改写。
3. 即便形态全对，yosys 对异步复位 always 内的 memory 写仍默认展开——
   **JPEG 脚本里的 `read_verilog -nomem2reg` 才是开关**，我们的脚本
   漏抄了这个 flag。

| 指标 | R4c（全 FF） | R4d（mem 提取） |
|---|---|---|
| cells | 449,550 | **211,676（−53%）** |
| 触发器 | 49,049 | **4,229（−91%）** |
| 逻辑面积 | 44,838 µm² | 17,364 µm² |
| SRAM 外挂（fakeram+flop-RF，8 块） | — | 5,137 µm² |
| **总面积** | 44,838 µm² | **22,501 µm²（−50%）** |
| Fmax | 298 MHz | **301 MHz（300 达标）** |
| **综合时间** | ~50 分钟 | **3 分钟（~17×）** |

29 个 $mem_v2 保留（含小数组；大块 8 个按 fakeram/flop-RF 估价如上）。
回归零退步：40/40 + 38/38。

## R4e — 输入加宽 32-bit（已完成）

bitreader 字喂入（in_word[31:0]+in_bytes，尾部字节 RTL 内 mask 防御）。
首版踩坑：64b 缓冲下接收窗（fill≤32）与饥饿门槛（avail≥24）只隔
8 bits，形成消费-停-填振荡反而更慢——**缓冲扩到 96b** 后窗口宽裕。

周期对账揭示了 R4d 的隐性代价：64x64 帧 4566→5014 拍的差额恰好
= (27 拍串行清零 + 1 拍预取) × 16 MB = 448——全部来自 R4d，R4e 本身
在高码率流（q2）上微正收益。综合中性：210,192 cells / 299 MHz /
17,222 µm²。回归全绿（74,978 块 + 40/40 + 38/38）。

## R4f — cram 双缓冲 + 解析/重建流水（已完成）

cram 拆 A/B bank：mb_dec 向一个 bank 填下一 MB 的系数，同时 mb_recon
重建（并随后清零）另一个。握手从"等重建完成"缩短为"等头部被接受"
（接受拍翻 bank），mb_dec 与 mb_recon 形成真 MB 级流水——rtl_spec
当初画的三段流水愿景落地了一段。deblock push 改用 recon 的锁存坐标；
frame_go 等 recon 排空（解析先于最后一个重建结束）。

两个握手 bug 由回归当场抓获：
1. mb_valid 单拍脉冲 → 消费者错过 → 经典 valid/ready 死锁（持有至
   接受）；
2. 接受脉冲落在 S_EMIT 拍而推进逻辑只在 S_WAIT_REC 监听 → 错过后
   重建结束被**二次接受**，空 bank 覆盖输出（trace 里两个 ACCEPT
   mbx=0 一目了然）。S_EMIT 拍直接响应接受。

| 指标 | R4e | R4f |
|---|---|---|
| 64x64 帧周期 | 5014 | **4262（−15%，优于 R4d 之前的 4566）** |
| 48x48 q2 帧周期 | 12620 | **11964（历史最佳）** |
| Fmax | 299 MHz | **301 MHz** |
| 逻辑面积 | 17,222 µm² | 17,472 µm²（双 bank +1.4%） |

R4d 的 28 拍/MB 隐性代价全部收回且有富余。回归全绿。

## R4g — deblock 流式重构 + 完整核综合（已完成）

deblock_stream.sv 取代帧缓冲架构进入综合范围：cur/left MB 寄存对 +
mb_w 行缓冲（宽字 mem），垂直边对左邻寄存即滤、水平边 0 对行缓冲
（上邻已完成态），输出滞后一 MB 行的行流协议。修改链闭合性与 C 的
光栅序逐 MB 语义逐边验证等价。h264_core 自此是**完整解码器**：
码流进、滤波后行流出，内部只有行缓冲（1080p 支持，无帧存储）。

第一发即 bit-exact（64x64 deblock-on）；core-regress 40/40——含
旧帧缓冲架构测不了的 >320 宽向量。两个 sv2v/yosys 坑：数组字的动态
part-select 写转成让 yosys 内核断言的 $shl（→ 纯字节数组形态）；
mem 在异步复位块清零非法（row_vld → 打包位向量）。

| 指标 | R4f（无 deblock） | R4g（完整核） |
|---|---|---|
| cells | 214,300 | 225,654 |
| FF | ~4.2K | 4,598 |
| mem 实例 | 29 | **47**（+deblock 行缓冲） |
| 逻辑面积 | 17,472 µm² | 18,415 µm² |
| SRAM 外挂 | 5,137 µm² | **21,149 µm²**（dbf 行缓冲 1080p 占 15.6k） |
| **总面积** | 22.6k µm² | **39.6k µm²** |
| Fmax | 301 MHz | **301 MHz** |
| 64x64 帧周期 | 4262（不含滤波） | **3993（滤波重叠在解码中）** |

## R4 总账（vs R3c 基线）

完整核（含 deblock）39.6k µm² @ 301 MHz，而 R3c 的 44.7k µm² @
286 MHz 还**不含** deblock。periods/frame 64x64：4522 → 3993。

## R4h — 邻行缓冲合并（已完成）

mb_dec 的 4 个窄行缓冲（i4_top 16b / nzl_top 20b / nzc_top×2 10b）
打包成单个 56b 宽字 mem（读写本就同拍同地址——零 FSM 改动）：
flop-RF 计价 3,391 µm² → 单 fakeram_64x28 宏 301 µm²。

**完整核终态：225,903 cells / 44 mem / 300 MHz /
逻辑 18,435 + SRAM 18,059 = 36,494 µm²**——比 R3c 不含 deblock 的
44.7k µm² 还小 18%，功能却是完整解码器。

## 余项（按需）

recon/deblock 内部并行化（更高吞吐时再做）。
