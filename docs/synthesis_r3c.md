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

## 下一步（R4 候选）

1. 行缓冲/cram SRAM 化 + FF 削减
2. dequant→IDCT 一级流水（300 MHz+ 收敛）
3. cavlc_block 每拍一语法元素（去 `!req_valid` 等待拍）
4. deblock_frame 流式行缓冲重构 + 并入综合
