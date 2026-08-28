// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_sound_mixer (
    input  logic signed [15:0] opm_l,
    input  logic signed [15:0] opm_r,
    input  logic signed [13:0] oki_mono,
    input  logic               fm_enable,
    input  logic               fx_enable,
    input  logic        [ 1:0] fx_level,
    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r
);

logic signed [19:0] opm_l_term;
logic signed [19:0] opm_r_term;
logic signed [19:0] oki_raw_term;
logic signed [19:0] oki_term;
logic signed [19:0] mix_sum;
logic signed [19:0] mix_scaled;
logic signed [15:0] mono;

always_comb begin
    // MAME normalizes YM samples by 32768 and OKI samples by 2048, then
    // routes each YM output and OKI to the mono speaker at gain 0.5.
    opm_l_term = fm_enable ? {{4{opm_l[15]}}, opm_l} : 20'sd0;
    opm_r_term = fm_enable ? {{4{opm_r[15]}}, opm_r} : 20'sd0;
    oki_raw_term = {{6{oki_mono[13]}}, oki_mono};

    // JTFrame FX levels 0/1/2/3 are Very Low/Low/High/Very High.
    // High is the exact MAME route. The other user selections scale only
    // the OKI contribution by 0.5/0.75/2.0 respectively.
    unique case (fx_level)
        2'd0:    oki_term = oki_raw_term <<< 3;
        2'd1:    oki_term = (oki_raw_term <<< 3) +
                            (oki_raw_term <<< 2);
        2'd3:    oki_term = oki_raw_term <<< 5;
        default: oki_term = oki_raw_term <<< 4;
    endcase
    if (!fx_enable)
        oki_term = 20'sd0;

    mix_sum = opm_l_term + opm_r_term + oki_term;

    // C++'s final float-to-int conversion truncates toward zero. Adding one
    // before an arithmetic divide handles both odd and even negative sums.
    mix_scaled = (mix_sum < 0) ?
                 ((mix_sum + 20'sd1) >>> 1) : (mix_sum >>> 1);

    if (mix_scaled > 20'sd32767)
        mono = 16'sh7fff;
    else if (mix_scaled < -20'sd32768)
        mono = 16'sh8000;
    else
        mono = mix_scaled[15:0];

    audio_l = mono;
    audio_r = mono;
end

endmodule
