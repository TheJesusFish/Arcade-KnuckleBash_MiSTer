derive_pll_clocks
derive_clock_uncertainty

create_generated_clock -name SDRAM_CLK -source \
    [get_pins {emu|pll|raizingpll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -divide_by 1 \
    [get_ports SDRAM_CLK]

# The external SDRAM clock is the shifted 94.5 MHz PLL output while the
# controller state machine runs from the related unshifted output.
set_multicycle_path -from [get_clocks {SDRAM_CLK}] \
    -to [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -setup -end 2
set_multicycle_path -from [get_clocks {SDRAM_CLK}] \
    -to [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -hold -end 2

# The copied sys_top.sdc still groups *|pll|pll_inst, while this core uses
# raizingpll_inst. Keep the two Raizing outputs related and cut unrelated
# framework, HDMI, audio, SPI, and HPS clock domains.
set_clock_groups -exclusive \
    -group [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk emu|pll|raizingpll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk SDRAM_CLK}] \
    -group [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] \
    -group [get_clocks {pll_audio|pll_audio_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -group [get_clocks {spi_sck}] \
    -group [get_clocks {hdmi_sck}] \
    -group [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] \
    -group [get_clocks {FPGA_CLK1_50}] \
    -group [get_clocks {FPGA_CLK2_50}] \
    -group [get_clocks {FPGA_CLK3_50}]

# SDRAM64 pad/controller paths for the board-local wrapper hierarchy.
set_multicycle_path -setup -end -from [get_keepers {SDRAM_DQ[*]}] \
    -to [get_keepers {emu:emu|knuckle_bash_sdram:u_sdram_mem|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|dout[*]}] 2
set_multicycle_path -hold -end -from [get_keepers {SDRAM_DQ[*]}] \
    -to [get_keepers {emu:emu|knuckle_bash_sdram:u_sdram_mem|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|dout[*]}] 2

set_multicycle_path -setup -end \
    -from [get_keepers {emu:emu|knuckle_bash_sdram:u_sdram_mem|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|dq_pad[*]}] \
    -to [get_keepers {SDRAM_DQ[*]}] 2
set_multicycle_path -hold -end \
    -from [get_keepers {emu:emu|knuckle_bash_sdram:u_sdram_mem|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|dq_pad[*]}] \
    -to [get_keepers {SDRAM_DQ[*]}] 2

set_multicycle_path -setup -end \
    -from [get_keepers {emu:emu|knuckle_bash_sdram:u_sdram_mem|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|sdram_a[12]}] \
    -to [get_keepers {SDRAM_DQMH}] 2
set_multicycle_path -hold -end \
    -from [get_keepers {emu:emu|knuckle_bash_sdram:u_sdram_mem|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|sdram_a[12]}] \
    -to [get_keepers {SDRAM_DQMH}] 2
set_multicycle_path -setup -end \
    -from [get_keepers {emu:emu|knuckle_bash_sdram:u_sdram_mem|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|sdram_a[11]}] \
    -to [get_keepers {SDRAM_DQML}] 2
set_multicycle_path -hold -end \
    -from [get_keepers {emu:emu|knuckle_bash_sdram:u_sdram_mem|jtframe_board_sdram:u_sdram|jtframe_sdram64:u_sdram|sdram_a[11]}] \
    -to [get_keepers {SDRAM_DQML}] 2

# fx68k documents the instruction-register to micro/nano address decode as a
# two-cycle path; the microcode outputs are not consumed on the first cycle.
set_multicycle_path -start -setup \
    -from [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_main:u_main|knuckle_bash_main_cpu:u_main_cpu|fx68k:u_cpu|Ir[*]}] \
    -to [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_main:u_main|knuckle_bash_main_cpu:u_main_cpu|fx68k:u_cpu|microAddr[*]}] 2
set_multicycle_path -start -hold \
    -from [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_main:u_main|knuckle_bash_main_cpu:u_main_cpu|fx68k:u_cpu|Ir[*]}] \
    -to [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_main:u_main|knuckle_bash_main_cpu:u_main_cpu|fx68k:u_cpu|microAddr[*]}] 1
set_multicycle_path -start -setup \
    -from [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_main:u_main|knuckle_bash_main_cpu:u_main_cpu|fx68k:u_cpu|Ir[*]}] \
    -to [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_main:u_main|knuckle_bash_main_cpu:u_main_cpu|fx68k:u_cpu|nanoAddr[*]}] 2
set_multicycle_path -start -hold \
    -from [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_main:u_main|knuckle_bash_main_cpu:u_main_cpu|fx68k:u_cpu|Ir[*]}] \
    -to [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_main:u_main|knuckle_bash_main_cpu:u_main_cpu|fx68k:u_cpu|nanoAddr[*]}] 1

# The compact V25 advances only when the 16 MHz enable is asserted. Keep this
# exception inside the CPU engine so wrapper buses and audio/shared-RAM
# interfaces remain single-cycle constrained.
set v25_cpu_keepers [get_keepers {emu:emu|knuckle_bash_game:u_game|knuckle_bash_sound:u_sound|knuckle_bash_v25_cpu:u_v25|knuckle_bash_z8086:u_cpu|*}]
set_multicycle_path -setup -from $v25_cpu_keepers -to $v25_cpu_keepers 5
set_multicycle_path -hold  -from $v25_cpu_keepers -to $v25_cpu_keepers 4

# The skeleton raster outputs sample only on the 6.75 MHz pixel enable.
# 'de' is deliberately absent: game_de has no consumer in Arcade-KnuckleBash.sv,
# so synthesis removes the register and the filter would match no keeper.
set_multicycle_path -setup -end -from [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -to [get_keepers {emu:emu|knuckle_bash_game:u_game|red[*] emu:emu|knuckle_bash_game:u_game|green[*] emu:emu|knuckle_bash_game:u_game|blue[*] emu:emu|knuckle_bash_game:u_game|hs emu:emu|knuckle_bash_game:u_game|vs}] 14
set_multicycle_path -hold -end -from [get_clocks {emu|pll|raizingpll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -to [get_keepers {emu:emu|knuckle_bash_game:u_game|red[*] emu:emu|knuckle_bash_game:u_game|green[*] emu:emu|knuckle_bash_game:u_game|blue[*] emu:emu|knuckle_bash_game:u_game|hs emu:emu|knuckle_bash_game:u_game|vs}] 13

# Every register in the hq2x blender advances on ce_x4i. sys/scandoubler.v
# places it at pc_in == pixsz4, pixsz2, pixsz2+pixsz4 and pixsz. Both mixers
# take ce_pix from ce_mix (knuckle_bash_video.sv:48), which fires one clock in
# fourteen, so pixsz=14 puts ce_x4i at 3, 7, 10 and 14 and the blender always
# gets at least three master clocks between updates. The wildcard covers the
# analog and HDMI mixer instances alike. Does not hold before pixsz is first
# measured, which is display-only and self-clears. Scoped to blender-internal
# paths so the other scandoubler enables stay honest.
set hq2x_keepers [get_keepers {*|Hq2x:Hq2x|Blend:blender|*}]
set_multicycle_path -setup -from $hq2x_keepers -to $hq2x_keepers 3
set_multicycle_path -hold  -from $hq2x_keepers -to $hq2x_keepers 2

# hdmi_height/hdmi_width are registered copies of HEIGHT/VSET/WIDTH/HSET
# (sys/sys_top.v:909). sys_top.sdc already declares those sources false paths
# because they only change when the video mode changes; the derived registers
# were never given the same treatment, so the framebuffer offset arithmetic is
# timed as a live path. Extending the framework's existing claim one stage.
# A mode change can land a frame late in the offsets, which is display-only.
set_false_path -from [get_keepers {hdmi_height[*] hdmi_width[*]}]

# ioctl_index is written once per file on the FIO_FILE_INDEX command
# (sys/hps_io.sv:665) and held for the whole transfer; ioctl_download is set and
# cleared at transfer boundaries. Both are stable for millions of clocks before
# the SDRAM address path samples them. Claim two, which they trivially satisfy.
# jtframe_sdram64_init|init is deliberately excluded: it is a boot FSM that can
# advance on consecutive clocks.
set ioctl_static [get_keepers {*|hps_io:hps_io|ioctl_index[*] *|hps_io:hps_io|ioctl_download}]
set_multicycle_path -setup -from $ioctl_static 2
set_multicycle_path -hold  -from $ioctl_static 1

set_false_path -to [get_keepers {*altera_std_synchronizer:*|din_s1}]
