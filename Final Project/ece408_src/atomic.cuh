#ifndef MXNET_OPERATOR_NEW_FORWARD_CUH_
#define MXNET_OPERATOR_NEW_FORWARD_CUH_
#define TILE_WIDTH 16
 
#include <mxnet/base.h>
 
namespace mxnet
{
namespace op
{
 
__global__ void reduction_forward_kernel(float *y, const float *x, const float *k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    __shared__ float SM[C * K * K];
    /*
    Modify this function to implement the forward pass described in Chapter 16.
    We have added an additional dimension to the tensors to support an entire mini-batch
    The goal here is to be correct AND fast.
    We have some nice #defs for you below to simplify indexing. Feel free to use them, or create your own.
    */
    // y: output  B x M x H_out x W_out
    // x: input   B x C x H x W
    // k: filter  M x C x K x K
    //const int B = x.shape_[0]; batch size
    //const int M = y.shape_[1]; output channel
    //const int C = x.shape_[1]; input channel
    //const int H = x.shape_[2]; input height
    //const int W = x.shape_[3]; input width
    //const int K = k.shape_[3]; filter size
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    (void)H_out; // silence declared but never referenced warning. remove this line when you start working
    (void)W_out; // silence declared but never referenced warning. remove this line when you start working
    const int W_grid = ceil(1.0 * W_out / TILE_WIDTH);
    const int H_grid = ceil(1.0 * H_out / TILE_WIDTH);

// An example use of these macros:
// float a = y4d(0,0,0,0)
// y4d(0,0,0,0) = a
#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]
 
    int n = blockIdx.x;
    int m = blockIdx.y;
    int h = blockIdx.z / W_out;
    int w = blockIdx.z % W_out;
    int c = threadIdx.x;
    int i = threadIdx.y;
    int j = threadIdx.z;
    //Represents for which output channel
    int t = threadIdx.x * K * K + threadIdx.y * K + threadIdx.z;

    float curRes = 0;

    if(h < H_out && w < W_out) {

        curRes += x4d(n, c, h + i, w + j) * k4d(m, c, i, j); 
        atomicAdd(&SM[0], curRes);
        
        __syncthreads();

        for(int stride = ceil(C * K * K) / 2; stride > 0; stride >>= 1) {
            __syncthreads();

            if(t < stride) {
                SM[t] += SM[t + stride];
            }
        }
    }
    
    if(t == 0)
        y4d(n, m, h, w) = SM[t];

#undef y4d
#undef x4d
#undef k4   
}

__global__ void atomic_forward_kernel(float *y, const float *x, const float *k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    __shared__ float SM[1];
    /*
    Modify this function to implement the forward pass described in Chapter 16.
    We have added an additional dimension to the tensors to support an entire mini-batch
    The goal here is to be correct AND fast.
    We have some nice #defs for you below to simplify indexing. Feel free to use them, or create your own.
    */
    // y: output  B x M x H_out x W_out
    // x: input   B x C x H x W
    // k: filter  M x C x K x K
    //const int B = x.shape_[0]; batch size
    //const int M = y.shape_[1]; output channel
    //const int C = x.shape_[1]; input channel
    //const int H = x.shape_[2]; input height
    //const int W = x.shape_[3]; input width
    //const int K = k.shape_[3]; filter size
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

// An example use of these macros:
// float a = y4d(0,0,0,0)
// y4d(0,0,0,0) = a
#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]
 
    int n = blockIdx.x;
    int m = blockIdx.y;
    int h = blockIdx.z / W_out;
    int w = blockIdx.z % W_out;
    int c = threadIdx.x;
    int i = threadIdx.y;
    int j = threadIdx.z;

    //Represents for which output channel
    int outputC = blockIdx.z;

    float curRes = 0;

    if(h < H_out && w < W_out) {

        curRes += x4d(n, c, h + i, w + j) * k4d(m, c, i, j); 
        atomicAdd(&SM[0], curRes);
        
        __syncthreads();
        if(threadIdx.x == 0 && threadIdx.y == 0 && threadIdx.z == 0)
            y4d(n, m, h, w) = SM[0];
    }
    

#undef y4d
#undef x4d
#undef k4   
}

 
/* 
   This function is called by new-inl.h
   Any code you write should be executed by this function.
   For ECE408, we only expect the float version of the operator to be called, so here we specialize with only floats.
*/
template <>
void forward<gpu, float>(mshadow::Tensor<gpu, 4, float> &y, const mshadow::Tensor<gpu, 4, float> &x, const mshadow::Tensor<gpu, 4, float> &w)
{
 
    // Use mxnet's CHECK_EQ to do assertions.
    // Remove this assertion when you do your implementation!
    // CHECK_EQ(0, 1) << "Remove this line and replace with your implementation";
 
    // Extract the tensor dimensions into B,M,C,H,W,K
    const int B = x.shape_[0]; //batch size
    const int M = y.shape_[1]; //output channel
    const int C = x.shape_[1]; //input channel
    const int H = x.shape_[2]; //input height
    const int W = x.shape_[3]; //input width
    const int K = w.shape_[3]; //filter size
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    int W_grid = ceil(1.0 * W_out / TILE_WIDTH);
    int H_grid = ceil(1.0 * H_out / TILE_WIDTH);
    int Z = H_grid * W_grid;
    // Set the kernel dimensions
    dim3 gridDim(B, M, H_out * W_out, TILE_WIDTH);
    dim3 blockDim(C / TILE_WIDTH, K, K);
 
    // Call the reduction kernel
    // reduction_forward_kernel<<<gridDim, blockDim>>>(y.dptr_,x.dptr_,w.dptr_, B,M,C,H,W,K);
    atomic_forward_kernel<<<gridDim, blockDim>>>(y.dptr_,x.dptr_,w.dptr_, B,M,C,H,W,K);
    // Use MSHADOW_CUDA_CALL to check for CUDA runtime errors.
    MSHADOW_CUDA_CALL(cudaDeviceSynchronize());
 
}
 
/* 
    This tells mxnet how to do an op when it's not a float.
    This is not used in the ECE408 project
*/
template <typename gpu, typename DType>
void forward(mshadow::Tensor<gpu, 4, DType> &y, const mshadow::Tensor<gpu, 4, DType> &x, const mshadow::Tensor<gpu, 4, DType> &w)
{
    // CHECK_EQ(0,1) << "Remove this line and replace it with your implementation.";
}
}
}
 
#endif
