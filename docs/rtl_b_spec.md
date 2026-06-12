# RTL Wave 16 — B 帧硬化规格（冻结）

## 子集 gate

CAVLC（W16-a..c）→ CABAC（W16-d），main profile，**nref 1/1**（单参考
双 list），**无加权**（wp=0、weightb=0——双向纯 avg），无 t8，单
slice/帧，spatial direct 先行（phase17），temporal direct 后补
（phase19，W16-c）。向量源：phase17 的 6 条 `*cavlc*` 流起步。

## 架构决策

1. **DPB 留系统侧**（与 P 的参考回写闭环一致延伸）：tb/系统维护
   最近两个参考帧（L0[0]=前向最近、L1[0]=后向最近，POC 序由系统按
   slice 头排序），MC 行读通道增加 `list` 维度（1b）。
2. **colocated MV 通道**（spatial direct 的 colZero / temporal 的
   缩放源）：RTL 已输出每 MB 的最终 MV 场（mv_pred）——系统侧收集
   参考帧的 MV/ref 场；B 解码时核发 colocated 查询
   `col_req(mbx,mby)` → `col_rsp`（4 个 8x8 角块的 {ref[1:0],
   mvx, mvy}，list1[0] 帧）。每 direct MB 一次。
3. **mv_pred 双 list 化**：行缓冲/左列/TL 增加 list1 平面（inter
   位 per list = ref≥0）；中值预测 per list 独立跑（现有数据通路
   ×2 时分复用，不复制组合）；direct-spatial 推导单元新增
   （16x16 邻块 ref min per list + colZero 8x8 粒度覆盖）。
4. **双向 MC**：mb_recon S_MC 循环加 list 维度——per 4x4 块按预测
   模式（L0/L1/Bi 2b，来自 mv_pred 的块模式场）取 1 或 2 次窗口，
   Bi 时 `(p0 + p1 + 1) >> 1` 平均（无加权 gate 下精确）。
5. **POC/输出重排留系统侧**：tb 按解码序喂 slice、按 POC 重排
   输出比对（h264_decode 的输出已是显示序——tb 维护解码序→显示序
   映射）。

## 语法范围

- CAVLC B mb_type：ue 映射（0=direct16x16、1/2 L0/L1 16x16、3 Bi、
  4..21 分区/方向组合、≥23 → intra），B sub_mb_type 13 类。
  从 c_model decoder.c 的映射逻辑生成 ROM（单一可信源）。
- mvd：按分区按 list（Bi 分区两组）；ref_idx nref=1 不编码。
- B_Skip / B_Direct_16x16 / B_Direct_8x8：spatial direct 推导。
- CABAC（W16-d）：mb_type 树 27..32（含 bdirect 邻块 inc）、
  sub 36..39、skip 24..26；mvd/cbf 复用现有 ctx 通路。

## 切片与验收

| 阶段 | 内容 | 验收 |
|---|---|---|
| W16-a | mb_dec CAVLC B 语法 + mv_pred 双 list + spatial direct | B 语法/MV dump 逐 MB bit-exact（DUMP_P 扩 B 记录两 list） |
| W16-b | mb_recon 双向 MC + avg + h264_core 集成（list 通道、tb DPB） | phase17 CAVLC B 多帧流帧级 yuv bit-exact |
| W16-c | temporal direct（colocated 通道 + POC 缩放） | phase19 CAVLC 流帧级 bit-exact |
| W16-d | CABAC B 语法 + 双熵 B | phase17/19 全熵 B 流帧级 bit-exact |

## 已知风险

- spatial direct 的 colZero 依赖 colocated 通道时序（MB 解析早期
  需要）——预取：MB 开始时（S_PRE 阶段）发 col 查询。
- B 的 mv_pred「only-A」与方向规则同 P；ref min 推导用 -1 哨兵
  （C mv_nbr 的 ref 语义已复刻）。
- direct 8x8 推导粒度：direct_8x8_inference=1（x264 恒置）——
  colocated 取 8x8 角块（C b_spatial_direct 同）。
