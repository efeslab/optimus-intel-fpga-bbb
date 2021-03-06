## Generated by import_user_clk_sdc.tcl during BBS build

##
## Global namespace for defining some static properties of user clocks,
## used by other user clock management scripts.
##
namespace eval userClocks {
    variable u_clkdiv2_name {uClk_usrDiv2}
    variable u_clk_name {uClk_usr}
    variable u_clkdiv2_fmax 600
    variable u_clk_fmax 600

    # Auto mode faster than 500 MHz is triggering timing failures, so limit it
    # to 500 MHz on BDX.  Most AFUs are significantly slower than this anyway.
    variable u_clk_auto_fmax 500
}

##
## Constrain the user clocks given a list of targets, ordered low to high.
##
proc constrain_user_clks { u_clks } {
    global ::userClocks

    set u_clk_low_mhz [lindex $u_clks 0]
    set u_clk_high_mhz [lindex $u_clks 1]

    set mult_low [expr {int(ceil(100.0 * $u_clk_low_mhz))}]
    set mult_high [expr {int(ceil(100.0 * $u_clk_high_mhz))}]

    create_generated_clock -name {uClk_usrDiv2} -source [get_pins {bot_wcp|top_qph|s45_reset_qph|clk_user_qph|qph_user_clk_fpll_u0|xcvr_fpll_a10_0|fpll_refclk_select_inst|iqtxrxclk[1]}] -duty_cycle 50/1 -multiply_by ${mult_low} -divide_by 23674 -master_clock {bot_wcp|top_qph|s45_reset_qph|clk_user_qph|SR_11234840_hack_fpll_u0|xcvr_fpll_a10_0|hssi_pll_cascade_clk} [get_pins {bot_wcp|top_qph|s45_reset_qph|clk_user_qph|qph_user_clk_fpll_u0|xcvr_fpll_a10_0|fpll_inst|outclk[0]}] 
    create_generated_clock -name {uClk_usr} -source [get_pins {bot_wcp|top_qph|s45_reset_qph|clk_user_qph|qph_user_clk_fpll_u0|xcvr_fpll_a10_0|fpll_refclk_select_inst|iqtxrxclk[1]}] -duty_cycle 50/1 -multiply_by ${mult_high} -divide_by 23674 -master_clock {bot_wcp|top_qph|s45_reset_qph|clk_user_qph|SR_11234840_hack_fpll_u0|xcvr_fpll_a10_0|hssi_pll_cascade_clk} [get_pins {bot_wcp|top_qph|s45_reset_qph|clk_user_qph|qph_user_clk_fpll_u0|xcvr_fpll_a10_0|fpll_inst|outclk[1]}] 
}
