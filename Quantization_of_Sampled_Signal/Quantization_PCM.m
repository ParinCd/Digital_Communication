% =========================================================================
% Experiment: Simulation of Sampling and Quantization using PCM and DPCM
% Tool: GNU Octave
% =========================================================================
clear; clc; close all;

% -------------------------------------------------------------------------
% 0. HELPER FUNCTIONS (self-contained, no extra packages needed)
% -------------------------------------------------------------------------
% my_quantiz: mimics the behaviour of the 'communications' package quantiz()
%   Given input samples, a vector of decision boundaries (partition) and a
%   vector of reconstruction levels (codebook), returns the index of the
%   chosen level and the quantized value for every sample.
function [idx, qval] = my_quantiz(samples, partition, codebook)
    idx  = zeros(size(samples));
    qval = zeros(size(samples));
    for m = 1:numel(samples)
        idx(m) = sum(samples(m) > partition);   % how many boundaries exceeded
        qval(m) = codebook(idx(m) + 1);
    end
end

% my_de2bi: converts decimal indices to a binary matrix (MSB first),
% equivalent to de2bi(x, n, 'left-msb') from the communications package.
function bits = my_de2bi(dec_vals, n)
    bits = zeros(numel(dec_vals), n);
    for m = 1:numel(dec_vals)
        bits(m, :) = bitget(dec_vals(m), n:-1:1);
    end
end

% -------------------------------------------------------------------------
% 1. GENERATE MESSAGE (ANALOG) SIGNAL
% -------------------------------------------------------------------------
fm      = 10;                  % message frequency (Hz)
Am      = 1;                   % message amplitude
Fs_cont = 10000;                % "continuous" time resolution for plotting
t_cont  = 0:1/Fs_cont:0.2;      % analog time axis
x_analog = Am*sin(2*pi*fm*t_cont);

% -------------------------------------------------------------------------
% 2. SAMPLING
% -------------------------------------------------------------------------
Fs = 200;                       % sampling frequency (Hz), > 2*fm (Nyquist)
Ts = 1/Fs;
t_sample = 0:Ts:0.2;
x_sample = Am*sin(2*pi*fm*t_sample);

figure;
subplot(2,1,1);
plot(t_cont, x_analog, 'b'); hold on;
stem(t_sample, x_sample, 'r', 'filled');
xlabel('Time (s)'); ylabel('Amplitude');
title('Sampling of Analog Signal');
legend('Analog signal','Sampled points');
grid on;

subplot(2,1,2);
stem(t_sample, x_sample, 'k', 'filled');
xlabel('Sample index (time)'); ylabel('Amplitude');
title('Discrete-Time Sampled Signal');
grid on;

% -------------------------------------------------------------------------
% 3. PCM QUANTIZATION
% -------------------------------------------------------------------------
n_bits = 4;                     % number of bits per sample
L = 2^n_bits;                   % number of quantization levels

Vmax =  Am;
Vmin = -Am;
delta = (Vmax - Vmin)/L;        % step size

% Uniform mid-rise quantizer
partition  = Vmin+delta : delta : Vmax-delta;   % decision boundaries
codebook   = Vmin+delta/2 : delta : Vmax-delta/2; % reconstruction levels

[index_pcm, x_pcm_quant] = my_quantiz(x_sample, partition, codebook);

% Convert quantizer index to binary PCM codewords
pcm_bits = my_de2bi(index_pcm, n_bits);
pcm_bitstream = reshape(pcm_bits.', 1, []);   % serial bit stream

figure;
subplot(2,1,1);
stairs(t_sample, x_pcm_quant, 'm', 'LineWidth', 1.5); hold on;
stem(t_sample, x_sample, 'b');
xlabel('Time (s)'); ylabel('Amplitude');
title(sprintf('PCM Quantization (%d bits, %d levels)', n_bits, L));
legend('Quantized (PCM) signal','Original samples');
grid on;

subplot(2,1,2);
stairs(pcm_bitstream, 'k', 'LineWidth', 1.2);
axis([0 80 -0.2 1.2]);
xlabel('Bit index'); ylabel('Bit value');
title('PCM Encoded Bitstream (first 80 bits)');
grid on;

% Quantization error and SQNR for PCM
error_pcm = x_sample - x_pcm_quant;
signal_power = mean(x_sample.^2);
noise_power_pcm = mean(error_pcm.^2);
SQNR_pcm_dB = 10*log10(signal_power/noise_power_pcm);
fprintf('--- PCM Results ---\n');
fprintf('Bits/sample     : %d\n', n_bits);
fprintf('Levels          : %d\n', L);
fprintf('Step size (delta): %.4f\n', delta);
fprintf('Measured SQNR   : %.2f dB\n', SQNR_pcm_dB);
fprintf('Theoretical SQNR: %.2f dB\n\n', 6.02*n_bits + 1.76);

% -------------------------------------------------------------------------
% 4. DPCM (DIFFERENTIAL PCM)
% -------------------------------------------------------------------------
% DPCM quantizes the DIFFERENCE between the current sample and a
% predicted value (here, a simple 1st-order predictor = previous
% reconstructed sample).

N = length(x_sample);
x_dpcm_recon = zeros(1, N);   % reconstructed signal at receiver
pred = zeros(1, N);           % predicted value
d = zeros(1, N);              % difference (prediction error) signal
d_quant = zeros(1, N);        % quantized difference

% Use a finer quantizer for the smaller-range difference signal
d_range = max(abs(diff(x_sample))) * 1.2;   % estimate range of differences
delta_d = 2*d_range / L;
partition_d = -d_range+delta_d : delta_d : d_range-delta_d;
codebook_d  = -d_range+delta_d/2 : delta_d : d_range-delta_d/2;

for k = 1:N
    if k == 1
        pred(k) = 0;                 % initial prediction
    else
        pred(k) = x_dpcm_recon(k-1); % predictor = previous reconstruction
    end
    d(k) = x_sample(k) - pred(k);              % prediction error
    [~, d_quant(k)] = my_quantiz(d(k), partition_d, codebook_d); % quantize error
    x_dpcm_recon(k) = pred(k) + d_quant(k);    % reconstruct signal
end

figure;
subplot(2,1,1);
plot(t_sample, x_sample, 'b-o'); hold on;
plot(t_sample, x_dpcm_recon, 'r-*');
xlabel('Time (s)'); ylabel('Amplitude');
title('DPCM: Original vs Reconstructed Signal');
legend('Original samples','DPCM reconstructed');
grid on;

subplot(2,1,2);
stairs(t_sample, d, 'g'); hold on;
stairs(t_sample, d_quant, 'k');
xlabel('Time (s)'); ylabel('Amplitude');
title('DPCM: Prediction Error (Difference Signal)');
legend('Difference signal','Quantized difference');
grid on;

% Quantization error and SQNR for DPCM
error_dpcm = x_sample - x_dpcm_recon;
noise_power_dpcm = mean(error_dpcm.^2);
SQNR_dpcm_dB = 10*log10(signal_power/noise_power_dpcm);
fprintf('--- DPCM Results ---\n');
fprintf('Bits/sample (for difference signal): %d\n', n_bits);
fprintf('Measured SQNR : %.2f dB\n\n', SQNR_dpcm_dB);

% -------------------------------------------------------------------------
% 5. COMPARISON
% -------------------------------------------------------------------------
fprintf('--- Comparison ---\n');
fprintf('PCM  SQNR : %.2f dB\n', SQNR_pcm_dB);
fprintf('DPCM SQNR : %.2f dB\n', SQNR_dpcm_dB);
if SQNR_dpcm_dB > SQNR_pcm_dB
    fprintf('=> DPCM performs better for this correlated (sinusoidal) signal.\n');
else
    fprintf('=> PCM performs better for this signal.\n');
end

% -------------------------------------------------------------------------
% 6. SQNR vs NUMBER OF QUANTIZATION/ENCODING BITS
% -------------------------------------------------------------------------
% Sweep bit depth and recompute SQNR for PCM, DPCM, and the theoretical
% formula, then plot all three together.

bits_range = 2:1:10;                 % bit depths to test
SQNR_pcm_sweep  = zeros(size(bits_range));
SQNR_dpcm_sweep = zeros(size(bits_range));
SQNR_theory_sweep = 6.02*bits_range + 1.76;

for b_idx = 1:length(bits_range)
    nb = bits_range(b_idx);
    Lb = 2^nb;

    % ---- PCM quantizer for this bit depth ----
    delta_b = (Vmax - Vmin)/Lb;
    partition_b = Vmin+delta_b : delta_b : Vmax-delta_b;
    codebook_b  = Vmin+delta_b/2 : delta_b : Vmax-delta_b/2;
    [~, x_pcm_b] = my_quantiz(x_sample, partition_b, codebook_b);

    err_pcm_b = x_sample - x_pcm_b;
    SQNR_pcm_sweep(b_idx) = 10*log10(signal_power/mean(err_pcm_b.^2));

    % ---- DPCM quantizer for this bit depth ----
    delta_db = 2*d_range / Lb;
    partition_db = -d_range+delta_db : delta_db : d_range-delta_db;
    codebook_db  = -d_range+delta_db/2 : delta_db : d_range-delta_db/2;

    x_dpcm_b = zeros(1, N);
    for k = 1:N
        if k == 1
            pred_b = 0;
        else
            pred_b = x_dpcm_b(k-1);
        end
        diff_b = x_sample(k) - pred_b;
        [~, diff_q_b] = my_quantiz(diff_b, partition_db, codebook_db);
        x_dpcm_b(k) = pred_b + diff_q_b;
    end

    err_dpcm_b = x_sample - x_dpcm_b;
    SQNR_dpcm_sweep(b_idx) = 10*log10(signal_power/mean(err_dpcm_b.^2));
end

figure;
plot(bits_range, SQNR_pcm_sweep,   'b-o', 'LineWidth', 1.5); hold on;
plot(bits_range, SQNR_dpcm_sweep,  'r-s', 'LineWidth', 1.5);
plot(bits_range, SQNR_theory_sweep,'k--', 'LineWidth', 1.5);
xlabel('Number of quantization/encoding bits (n)');
ylabel('SQNR (dB)');
title('SQNR vs Number of Quantization Bits');
legend('PCM (measured)', 'DPCM (measured)', ...
       'Theoretical (6.02n + 1.76 dB)', 'Location', 'northwest');
grid on;

fprintf('--- SQNR vs Bits Table ---\n');
fprintf('%6s %12s %12s %12s\n', 'Bits', 'PCM(dB)', 'DPCM(dB)', 'Theory(dB)');
for b_idx = 1:length(bits_range)
    fprintf('%6d %12.2f %12.2f %12.2f\n', bits_range(b_idx), ...
            SQNR_pcm_sweep(b_idx), SQNR_dpcm_sweep(b_idx), SQNR_theory_sweep(b_idx));
end
