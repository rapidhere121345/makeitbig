# 地面去方框修正

内置 imagegen；输入为 `sources/ground_source_original.png`，只修地面。
离线重复铺图发现原源图外沿浅色方框，不符合安静地面要求。

```text
Use case: precise-object-edit. Asset type: seamless pixel game ground texture. Edit target is supplied cold ground texture. Fix ONLY its heavy square frame, smooth grain and excess texture. REMOVE the entire lighter perimeter frame; fill the whole canvas edge-to-edge with the SAME flat charcoal #2D3943 that dominates the interior. There must be absolutely NO frame, border, tile grid, shadow rim, vignette, bevel or rectangular inset. One single seamless texture, NOT a sheet or sample board. More than 96 percent of area perfectly flat #2D3943, with only 3 irregular very sparse chunky patches #29343E and #33404A and one tiny short angular crack #202A33. True hard pixel clusters on logical64x64 grid uniformly enlarged, not fine dithering, not paper grain, not smooth shading. Keep entire outer 10 percent perimeter exactly the same flat background color as the center, invisible as a band because most of center same color too. Patches/crack only away from all edges. No snow, rocks, plants, perspective, lighting, text, labels, props or ground objects. Opaque square PNG. Final repeated ground must read as one uninterrupted quiet cold slate waste, never tiles.
```
