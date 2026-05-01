import cv2
import numpy as np

# --- CONFIGURATION ---
INPUT_FILE = 'template_banana.png'
KERNEL_SIZE = 28  # Match your FPGA sliding window size
BIT_WIDTH = 4      # 4-bit signed: range is -8 to +7 (we'll use -7 to +7 for symmetry)
OUTPUT_VERILOG = "kernel_weights_4bit.txt"

def generate_4bit_weights():
    # 1. Load the image in Grayscale
    img = cv2.imread(INPUT_FILE, cv2.IMREAD_GRAYSCALE)
    if img is None:
        print(f"Error: Could not find {INPUT_FILE}")
        return

    # 2. Resize to Kernel Size
    resized = cv2.resize(img, (KERNEL_SIZE, KERNEL_SIZE), interpolation=cv2.INTER_AREA)

    # 3. Mean Subtraction (Crucial for Matched Filtering)
    weights_float = resized.astype(np.float32)
    weights_float -= np.mean(weights_float)

    # 4. Flip for Convolution (Horizontal + Vertical)
    # This allows a Convolution Engine to behave like a Correlation Matcher
    weights_float = cv2.flip(weights_float, -1)

    # 5. 4-Bit Quantization Logic
    max_val = np.max(np.abs(weights_float))
    if max_val > 0:
        # Scale to fit -7 to +7
        scale_factor = (2**(BIT_WIDTH-1) - 1) / max_val
        quantized_weights = np.round(weights_float * scale_factor).astype(np.int8)
    else:
        quantized_weights = np.zeros((KERNEL_SIZE, KERNEL_SIZE), dtype=np.int8)

    # 6. Generate SystemVerilog Output
    flat_weights = quantized_weights.flatten()
    
    with open(OUTPUT_VERILOG, "w") as f:
        f.write(f"// FPGA 4-bit Matched Filter Weights for {INPUT_FILE}\n")
        f.write(f"// Weights range: -7 to +7\n")
        f.write("localparam signed [3:0] BANANA_KERNEL [0:{}] = '{{\n".format(len(flat_weights)-1))
        
        for i in range(len(flat_weights)):
            # Format with 3 spaces for readability
            f.write(f"{flat_weights[i]:2d}")
            if i < len(flat_weights) - 1:
                f.write(", ")
            if (i + 1) % KERNEL_SIZE == 0:
                f.write("\n")
        
        f.write("};")

    print(f"Success! 4-bit weights written to {OUTPUT_VERILOG}")
    print(f"Max weight: {np.max(quantized_weights)}, Min weight: {np.min(quantized_weights)}")

if __name__ == "__main__":
    generate_4bit_weights()