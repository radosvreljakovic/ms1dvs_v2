clear all
close all
clc

coeffs_filename = 'avg.bin';
coeffs_frac_bits = 11;
input_filename = 'panorama.bin';
output_filename = 'panorama_avg_out.bin';
output_frac_bits = 5;

% Read filter coeffs
fp = fopen(coeffs_filename, 'rb');
filter_mask = reshape(fread(fp, 49, 'int16')/2^coeffs_frac_bits, [7 7])';
fclose(fp);

% Read input image
fp = fopen(input_filename, 'rb');
width = fread(fp, 1, 'uint32');
height = fread(fp, 1, 'uint32');
input_image = reshape(fread(fp, width*height, 'uint8'), [width height])';
fclose(fp);

% Read output image
fp = fopen(output_filename, 'rb');
width = fread(fp, 1, 'uint32');
height = fread(fp, 1, 'uint32');
output_image = reshape(fread(fp, width*height, 'int16')/2^output_frac_bits, [width height])';
fclose(fp);

% Process input image
ref_output = imfilter(input_image, filter_mask, 'replicate');

% Compare output and reference image
diff_image = ref_output - output_image;
figure; imshow(uint8(input_image)); title('Input image');
figure; imshow(uint8(ref_output)); title('Reference output image');
figure; imshow(uint8(output_image)); title('Nios2 output image');
figure; imagesc(diff_image); title('Difference image');

disp(['Maximal abs error: ', num2str(max(abs(diff_image(:))))])