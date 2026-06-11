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

## 下一步（R4 余项）

1. 行缓冲/cram SRAM 化 + FF 削减（49K FF 的大头）
2. req 路径 sizing 收回 300 MHz
3. 输入加宽(16/32-bit 喂入)解除填充瓶颈
4. deblock_frame 流式行缓冲重构 + 并入综合
