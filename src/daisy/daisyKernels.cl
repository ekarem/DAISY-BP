#define GRADIENT_NUM 8

#define CONVX_GROUP_SIZE_X 16
#define CONVX_GROUP_SIZE_Y 8
#define CONVX_WORKER_STEPS 4

__kernel void convolve_x7(__global   float * pyramidArray,
                          __constant float * fltArray,
                          const      int     pddWidth,
                          const      int     pddHeight)
{

  const int lx = get_local_id(0);
  const int ly = get_local_id(1);
  __local float lclArray[CONVX_GROUP_SIZE_Y][CONVX_GROUP_SIZE_X * (CONVX_WORKER_STEPS + 2)];

  const int srcOffsetX = (get_group_id(0) * CONVX_WORKER_STEPS-1) * CONVX_GROUP_SIZE_X + lx;
  const int srcOffset = get_global_id(1) * pddWidth + srcOffsetX;

  for(int i = 1; i < CONVX_WORKER_STEPS+1; i++)
    lclArray[ly][i * CONVX_GROUP_SIZE_X + lx] = pyramidArray[srcOffset + i * CONVX_GROUP_SIZE_X];

  lclArray[ly][lx] = (srcOffsetX >= 0 ? pyramidArray[srcOffset]:lclArray[ly][CONVX_GROUP_SIZE_X]);

  lclArray[ly][lx + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X] = (srcOffsetX + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X < pddWidth ? pyramidArray[srcOffset + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X]:lclArray[ly][(CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X-1]);

  barrier(CLK_LOCAL_MEM_FENCE);

  for(int w = 1; w < CONVX_WORKER_STEPS+1; w++){
    const int dstOffset = pddWidth * pddHeight + srcOffset;
    float s = 0;

    for(int i = lx-1; i < lx+2; i++)
      s += lclArray[ly][w * CONVX_GROUP_SIZE_X + i] * fltArray[i-lx+1];

    pyramidArray[dstOffset + w * CONVX_GROUP_SIZE_X] = s;
  }
}

#define CONVY_GROUP_SIZE_X 16
#define CONVY_GROUP_SIZE_Y 8
#define CONVY_WORKER_STEPS 4

__kernel void convolve_y7(__global   float * pyramidArray,
                          __constant float * fltArray,
                          const      int     pddWidth,
                          const      int     pddHeight)
{
  const int ly = get_local_id(1);
  const int lx = get_local_id(0);  
  __local float lclArray[CONVY_GROUP_SIZE_X][CONVY_GROUP_SIZE_Y * (CONVY_WORKER_STEPS+2) + 1];

  const int srcOffsetY = ((get_group_id(1) * CONVY_WORKER_STEPS-1) * CONVY_GROUP_SIZE_Y + ly);
  const int srcOffset =  srcOffsetY * pddWidth + get_global_id(0) + pddWidth * pddHeight;

  for(int i = 1; i < CONVY_WORKER_STEPS+1; i++)
    lclArray[lx][i * CONVY_GROUP_SIZE_Y + ly] = pyramidArray[srcOffset + i * CONVY_GROUP_SIZE_Y * pddWidth];

  lclArray[lx][ly] = (srcOffsetY >= 0 ? pyramidArray[srcOffset]:lclArray[lx][CONVY_GROUP_SIZE_Y]);

  lclArray[lx][(CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y + ly] = (srcOffsetY + (CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y < pddHeight ? pyramidArray[srcOffset + (CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y * pddWidth]:lclArray[lx][(CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y-1]);

  barrier(CLK_LOCAL_MEM_FENCE);

  for(int w = 1; w < CONVY_WORKER_STEPS+1; w++){
    const int dstOffset = srcOffset - pddWidth * pddHeight;
    float s = 0;

    for(int i = ly-1; i < ly+2; i++)
      s += lclArray[lx][w * CONVY_GROUP_SIZE_Y + i] * fltArray[i-ly+1];

    pyramidArray[dstOffset + w * CONVY_GROUP_SIZE_Y * pddWidth] = s;
  }
}

__kernel void gradient_all(__global float * pyramidArray,
                           const    int     pddWidth,
                           const    int     pddHeight,
                           const    int     dstGlobalOffset)
{

  const int r = get_global_id(0) / pddWidth;
  const int c = get_global_id(0) % pddWidth;
  const int srcOffset = r * pddWidth + c;

  float4 n;
  n.x = (c > 0           ? pyramidArray[srcOffset-1]:pyramidArray[srcOffset]);
  n.y = (r > 0           ? pyramidArray[srcOffset-pddWidth]:pyramidArray[srcOffset]);
  n.z = (c < pddWidth-1  ? pyramidArray[srcOffset+1]:pyramidArray[srcOffset]);
  n.w = (r < pddHeight-1 ? pyramidArray[srcOffset+pddWidth]:pyramidArray[srcOffset]);

  float8 gradients;
  const float8 angles = (float8)(0.0f, M_PI / 4, M_PI / 2, 3 * (M_PI / 4), M_PI,
                                  5 * (M_PI / 4), 3 * (M_PI / 2), 7 * (M_PI / 4));
  n.x = (n.z-n.x) * 0.5;
  n.y = (n.w-n.y) * 0.5;

  gradients.s0 = fmax(cos(angles.s0) * n.x + 
                      sin(angles.s0) * n.y, 0.0);
  gradients.s1 = fmax(cos(angles.s1) * n.x + 
                      sin(angles.s1) * n.y, 0.0);
  gradients.s2 = fmax(cos(angles.s2) * n.x + 
                      sin(angles.s2) * n.y, 0.0);
  gradients.s3 = fmax(cos(angles.s3) * n.x + 
                      sin(angles.s3) * n.y, 0.0);
  gradients.s4 = fmax(cos(angles.s4) * n.x + 
                      sin(angles.s4) * n.y, 0.0);
  gradients.s5 = fmax(cos(angles.s5) * n.x + 
                      sin(angles.s5) * n.y, 0.0);
  gradients.s6 = fmax(cos(angles.s6) * n.x + 
                      sin(angles.s6) * n.y, 0.0);
  gradients.s7 = fmax(cos(angles.s7) * n.x + 
                      sin(angles.s7) * n.y, 0.0);

  const int dstOffset = dstGlobalOffset + r * pddWidth + c;
  const int push = pddWidth * pddHeight;

  pyramidArray[dstOffset]        = gradients.s0;
  pyramidArray[dstOffset+push]   = gradients.s1;
  pyramidArray[dstOffset+2*push] = gradients.s2;
  pyramidArray[dstOffset+3*push] = gradients.s3;
  pyramidArray[dstOffset+4*push] = gradients.s4;
  pyramidArray[dstOffset+5*push] = gradients.s5;
  pyramidArray[dstOffset+6*push] = gradients.s6;
  pyramidArray[dstOffset+7*push] = gradients.s7;
}

#define CONVX_GROUP_SIZE_X 16
#define CONVX_GROUP_SIZE_Y 4
#define CONVX_WORKER_STEPS 4
#define DOWNSAMPLE_RATE 4
#define FILTER_RADIUS 6

__kernel void convolveDs_x(__global   float * pyramidArray,
                           const      int     pddWidth,
                           const      int     pddHeight,
                           const      int     srcGlobalOffset, // from [13x,B+],[23x,B],[29x,C]
                           __constant float * fltArray) // downsample in x dimension, should be 1 if no downsample, must be a power of 2
{

  const int lx = get_local_id(0);
  const int ly = get_local_id(1);
  __local float lclArray[CONVX_GROUP_SIZE_Y][CONVX_GROUP_SIZE_X * (CONVX_WORKER_STEPS + 2)];

  const int srcOffsetX = (get_group_id(0) * CONVX_WORKER_STEPS-1) * CONVX_GROUP_SIZE_X + lx;
  const int srcOffset = srcGlobalOffset + get_global_id(1) * pddWidth + srcOffsetX;

  for(int i = 1; i < CONVX_WORKER_STEPS+1; i++)
    lclArray[ly][i * CONVX_GROUP_SIZE_X + lx] = pyramidArray[srcOffset + i * CONVX_GROUP_SIZE_X];

  lclArray[ly][lx] = (srcOffsetX >= 0 ? pyramidArray[srcOffset]:lclArray[ly][CONVX_GROUP_SIZE_X]);

  lclArray[ly][lx + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X] = (srcOffsetX + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X < pddWidth ? pyramidArray[srcOffset + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X]:lclArray[ly][(CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X-1]);

  barrier(CLK_LOCAL_MEM_FENCE);

  // if worker local id is greater than the number of elements this group must output
  if(lx >= (CONVX_GROUP_SIZE_X * CONVX_WORKER_STEPS) / DOWNSAMPLE_RATE) return; 

  const int dstOffset = get_global_id(1) * (pddWidth / DOWNSAMPLE_RATE) + get_group_id(0) * ((CONVX_GROUP_SIZE_X * CONVX_WORKER_STEPS) / DOWNSAMPLE_RATE) + lx;
  for(int w = 1; w < CONVX_WORKER_STEPS + 1; w += DOWNSAMPLE_RATE){
    float s = 0;
    int f = lx * DOWNSAMPLE_RATE;
    for(int i = f - FILTER_RADIUS; i < f + FILTER_RADIUS + 1; i++)
      s += lclArray[ly][w * CONVX_GROUP_SIZE_X + i] * fltArray[i-f+FILTER_RADIUS];

    pyramidArray[dstOffset + ((w-1) / DOWNSAMPLE_RATE) * CONVX_GROUP_SIZE_X] = s;
  }
}

#define CONVY_GROUP_SIZE_Y 8
#define CONVY_WORKER_STEPS 8

__kernel void convolveDs_y(__global   float * pyramidArray,
                           const      int     pddWidth, // should be original width / downsampleRate
                           const      int     pddHeight,
                           const      int     dstGlobalOffset, // to [13y,B],[23y,C],[29y,D]
                           __constant float * fltArray)
{
  const int ly = get_local_id(1);
  const int lx = get_local_id(0);  
  __local float lclArray[CONVY_GROUP_SIZE_X][CONVY_GROUP_SIZE_Y * (CONVY_WORKER_STEPS+2) + 1];

  const int srcOffsetY = ((get_group_id(1) * CONVY_WORKER_STEPS) * CONVY_GROUP_SIZE_Y + ly);
  const int srcOffset =  srcOffsetY * pddWidth + get_global_id(0);

  for(int i = 0; i < CONVY_WORKER_STEPS; i++)
    lclArray[lx][(i+1) * CONVY_GROUP_SIZE_Y + ly] = pyramidArray[srcOffset + i * CONVY_GROUP_SIZE_Y * pddWidth];

  lclArray[lx][ly] = (get_group_id(1) % ((pddHeight / CONVY_WORKER_STEPS) / get_local_size(1)) ? pyramidArray[srcOffset-CONVY_GROUP_SIZE_Y*pddWidth]:lclArray[lx][CONVY_GROUP_SIZE_Y]);

  lclArray[lx][(CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y + ly] = ((srcOffsetY % pddHeight) + (CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y < pddHeight ? pyramidArray[srcOffset + CONVY_WORKER_STEPS * CONVY_GROUP_SIZE_Y * pddWidth]:lclArray[lx][(CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y-1]);

  barrier(CLK_LOCAL_MEM_FENCE);

  const int dstOffset = dstGlobalOffset + (get_group_id(1) * ((CONVY_GROUP_SIZE_Y * CONVY_WORKER_STEPS) / DOWNSAMPLE_RATE) + ly) * pddWidth + get_global_id(0);
  for(int w = 1; w < CONVY_WORKER_STEPS + 1; w += DOWNSAMPLE_RATE){
    float s = 0;
    int f = ly * DOWNSAMPLE_RATE;
    for(int i = f - FILTER_RADIUS; i < f + FILTER_RADIUS + 1; i++)
      s += lclArray[lx][w * CONVY_GROUP_SIZE_Y + i] * fltArray[i-f+FILTER_RADIUS];

    pyramidArray[dstOffset + ((w-1) / DOWNSAMPLE_RATE) * CONVY_GROUP_SIZE_Y * pddWidth] = s;
  }
}

//#define CONVX_WORKER_STEPS 8

__kernel void convolve_x23(__global   float * pyramidArray,
                           __constant float  * fltArray,
                           const      int     pddWidth,
                           const      int     pddHeight)
{

  const int lx = get_local_id(0);
  const int ly = get_local_id(1);
  __local float lclArray[CONVX_GROUP_SIZE_Y][CONVX_GROUP_SIZE_X * (CONVX_WORKER_STEPS + 2)];

  const int srcOffsetX = (get_group_id(0) * CONVX_WORKER_STEPS-1) * CONVX_GROUP_SIZE_X + lx;
  const int srcOffset = get_global_id(1) * pddWidth + srcOffsetX;

  for(int i = 1; i < CONVX_WORKER_STEPS+1; i++)
    lclArray[ly][i * CONVX_GROUP_SIZE_X + lx] = pyramidArray[srcOffset + i * CONVX_GROUP_SIZE_X];

  lclArray[ly][lx] = (srcOffsetX >= 0 ? pyramidArray[srcOffset]:lclArray[ly][CONVX_GROUP_SIZE_X]);

  lclArray[ly][lx + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X] = (srcOffsetX + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X < pddWidth ? pyramidArray[srcOffset + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X]:lclArray[ly][(CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X-1]);

  barrier(CLK_LOCAL_MEM_FENCE);

  fltArray += (7+11);

  for(int w = 1; w < CONVX_WORKER_STEPS+1; w++){
    const int dstOffset = pddWidth * pddHeight * 8 * 2 + srcOffset;
    float s = 0;

    for(int i = lx-11; i < lx+12; i++)
      s += lclArray[ly][w * CONVX_GROUP_SIZE_X + i] * fltArray[i-lx+11];

    pyramidArray[dstOffset + w * CONVX_GROUP_SIZE_X] = s;
  }
}

#define CONVY_GROUP_SIZE_Y 16
#define CONVY_WORKER_STEPS 4

__kernel void convolve_y23(__global   float * pyramidArray,
                           __constant float  * fltArray,
                           const      int     pddWidth,
                           const      int     pddHeight)
{

  const int ly = get_local_id(1);
  const int lx = get_local_id(0);  
  __local float lclArray[CONVY_GROUP_SIZE_X][CONVY_GROUP_SIZE_Y * (CONVY_WORKER_STEPS+2) + 1];

  const int srcOffsetY = ((get_group_id(1) * CONVY_WORKER_STEPS-1) * CONVY_GROUP_SIZE_Y + ly);
  const int srcOffset =  srcOffsetY * pddWidth + get_global_id(0) + pddWidth * pddHeight * 8 * 2;

  for(int i = 1; i < CONVY_WORKER_STEPS+1; i++)
    lclArray[lx][i * CONVY_GROUP_SIZE_Y + ly] = pyramidArray[srcOffset + i * CONVY_GROUP_SIZE_Y * pddWidth];

  lclArray[lx][ly] = (get_group_id(1) % ((pddHeight / CONVY_WORKER_STEPS) / get_local_size(1)) > 0 ? pyramidArray[srcOffset]:lclArray[lx][CONVY_GROUP_SIZE_Y]);

  lclArray[lx][(CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y + ly] = ((srcOffsetY % pddHeight) + (CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y < pddHeight ? pyramidArray[srcOffset + (CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y * pddWidth]:lclArray[lx][(CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y-1]);

  barrier(CLK_LOCAL_MEM_FENCE);

  fltArray += (7+11);

  for(int w = 1; w < CONVY_WORKER_STEPS+1; w++){
    const int dstOffset = srcOffset - pddWidth * pddHeight * 8;
    float s = 0;

    for(int i = ly-11; i < ly+12; i++)
      s += lclArray[lx][w * CONVY_GROUP_SIZE_Y + i] * fltArray[i-ly+11];

    pyramidArray[dstOffset + w * CONVY_GROUP_SIZE_Y * pddWidth] = s;
  }
}

//#define CONVX_WORKER_STEPS 8

__kernel void convolve_x29(__global   float * pyramidArray,
                           __constant float  * fltArray,
                           const      int     pddWidth,
                           const      int     pddHeight)
{

  const int lx = get_local_id(0);
  const int ly = get_local_id(1);
  __local float lclArray[CONVX_GROUP_SIZE_Y][CONVX_GROUP_SIZE_X * (CONVX_WORKER_STEPS + 2)];

  const int srcOffsetX = (get_group_id(0) * CONVX_WORKER_STEPS-1) * CONVX_GROUP_SIZE_X + lx;
  const int srcOffset = get_global_id(1) * pddWidth + srcOffsetX + pddWidth * pddHeight * 8;

  for(int i = 1; i < CONVX_WORKER_STEPS+1; i++)
    lclArray[ly][i * CONVX_GROUP_SIZE_X + lx] = pyramidArray[srcOffset + i * CONVX_GROUP_SIZE_X];

  lclArray[ly][lx] = (srcOffsetX >= 0 ? pyramidArray[srcOffset]:lclArray[ly][CONVX_GROUP_SIZE_X]);

  lclArray[ly][lx + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X] = (srcOffsetX + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X < pddWidth ? pyramidArray[srcOffset + (CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X]:lclArray[ly][(CONVX_WORKER_STEPS+1) * CONVX_GROUP_SIZE_X-1]);

  barrier(CLK_LOCAL_MEM_FENCE);

  fltArray += (7+11+23);

  for(int w = 1; w < CONVX_WORKER_STEPS+1; w++){
    const int dstOffset = pddWidth * pddHeight * 8 * 2 + srcOffset;
    float s = 0;

    for(int i = lx-14+1; i < lx+15-1; i++)
      s += lclArray[ly][w * CONVX_GROUP_SIZE_X + i] * fltArray[i-lx+14-1];

    pyramidArray[dstOffset + w * CONVX_GROUP_SIZE_X] = s;
  }
}

#define CONVY_WORKER_STEPS 4

__kernel void convolve_y29(__global   float * pyramidArray,
                           __constant float  * fltArray,
                           const      int     pddWidth,
                           const      int     pddHeight)
{

  const int ly = get_local_id(1);
  const int lx = get_local_id(0);
  __local float lclArray[CONVY_GROUP_SIZE_X][CONVY_GROUP_SIZE_Y * (CONVY_WORKER_STEPS+2) + 1];

  const int srcOffsetY = ((get_group_id(1) * CONVY_WORKER_STEPS-1) * CONVY_GROUP_SIZE_Y + ly);
  const int srcOffset =  srcOffsetY * pddWidth + get_global_id(0) + pddWidth * pddHeight * 8 * 3;

  for(int i = 1; i < CONVY_WORKER_STEPS+1; i++)
    lclArray[lx][i * CONVY_GROUP_SIZE_Y + ly] = pyramidArray[srcOffset + i * CONVY_GROUP_SIZE_Y * pddWidth];

  lclArray[lx][ly] = (get_group_id(1) % ((pddHeight / CONVY_WORKER_STEPS) / get_local_size(1)) > 0 ? pyramidArray[srcOffset]:lclArray[lx][CONVY_GROUP_SIZE_Y]);

  lclArray[lx][(CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y + ly] = ((srcOffsetY % pddHeight) + (CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y < pddHeight ? pyramidArray[srcOffset + (CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y * pddWidth]:lclArray[lx][(CONVY_WORKER_STEPS+1) * CONVY_GROUP_SIZE_Y-1]);

  barrier(CLK_LOCAL_MEM_FENCE);

  fltArray += (7+11+23);

  for(int w = 1; w < CONVY_WORKER_STEPS+1; w++){
    const int dstOffset = srcOffset - pddWidth * pddHeight * 8;
    float s = 0;

    for(int i = ly-14+1; i < ly+15-1; i++)
      s += lclArray[lx][w * CONVY_GROUP_SIZE_Y + i] * fltArray[i-ly+14-1];

    pyramidArray[dstOffset + w * CONVY_GROUP_SIZE_Y * pddWidth] = s;
  }
}

#define TOTAL_PETALS_NO 25
#define REGION_PETALS_NO 8
#define TRANS_GROUP_SIZE_X 32
#define TRANS_GROUP_SIZE_Y 8

__kernel void transposeGradients(__global float * srcArray,
                                 __global float * dstArray,
                                 const    int     srcWidth,
                                 const    int     srcHeight)
{

    const int smoothSectionHeight = srcHeight * GRADIENT_NUM;

    const int smoothSection = get_global_id(1) / smoothSectionHeight;

    const int groupRow = (get_global_id(1) % smoothSectionHeight) / 8;
    const int groupRowGradientSection = get_local_id(1);

    const int srcIndex = (smoothSection * smoothSectionHeight + groupRowGradientSection * srcHeight + groupRow) * srcWidth + get_global_id(0);

    __local float lclArray[(TRANS_GROUP_SIZE_X+2) * TRANS_GROUP_SIZE_Y];

    lclArray[get_local_id(1) * (TRANS_GROUP_SIZE_X+2) + get_local_id(0)] = srcArray[srcIndex];

    barrier(CLK_LOCAL_MEM_FENCE);

    const int localY = get_local_id(0) % TRANS_GROUP_SIZE_Y;
    const int localX = get_local_id(0) / TRANS_GROUP_SIZE_Y + get_local_id(1) * (TRANS_GROUP_SIZE_X / TRANS_GROUP_SIZE_Y);

    //
    // Normalisation piggy-backing along with the transposition
    //
    float l2normSum = .0f;
    for(int i = 0; i < GRADIENT_NUM; i++){
      const float g = lclArray[((localY+i) % GRADIENT_NUM) * (TRANS_GROUP_SIZE_X+2) + localX];
      l2normSum += g*g;
    }
    l2normSum = (l2normSum == 0.0 ? 1 : 1 / sqrt(l2normSum));
    //
    //

    const int dstRow = smoothSection * srcHeight + groupRow;
    const int dstCol = get_group_id(0) * TRANS_GROUP_SIZE_X * GRADIENT_NUM + localX * GRADIENT_NUM + localY;

    dstArray[dstRow * srcWidth * GRADIENT_NUM + dstCol] = lclArray[localY * (TRANS_GROUP_SIZE_X+2) + localX] * l2normSum; // this division... the division ALONE... seems to take 10 ms !!!
}

//#define TRANSD_BLOCK_WIDTH 512
#define TRANSD_DATA_WIDTH 16
#define TRANSD_PAIRS_OFFSET_WIDTH 1000
#define TRANSD_PAIRS_SINGLE_ONLY -999

__kernel void transposeDaisy(__global   float * srcArray,
                             __global   float * dstArray,
                             __constant int   * transArray,
                             __local    float * lclArray,
                             const      int     srcWidth,
                             const      int     srcHeight,
                             const      int     srcGlobalOffset,
                             const      int     transArrayLength,
                             const      int     lclArrayPadding) // either 0 or 8
{

  const int gx = get_global_id(0) - TRANSD_DATA_WIDTH; 
                                   // range across all blocks: [0, srcWidth+2*TRANSD_DATA_WIDTH-1] (pushed back to start from -TRANSD_DATA_WIDTH)
                                   // range for a block:
                                   // (same as for all blocks given that the blocks will now be rectangular --> whole rows)

  const int gy = get_global_id(1) - TRANSD_DATA_WIDTH; 
                                   // range across all blocks: [0, srcHeight+2*TRANSD_DATA_WIDTH-1] (pushed back to start from -TRANSD_DATA_WIDTH)
                                   // range for a block:
                                   // [k * TRANSD_BLOCK_WIDTH,
                                   //  min((k+1) * TRANSD_BLOCK_WIDTH + 2*TRANSD_DATA_WIDTH-1, srcHeight + 2*TRANSD_DATA_WIDTH-1)]

  const int lx = get_local_id(0);
  const int ly = get_local_id(1);

  //__local float lclArray[TRANSD_DATA_WIDTH * (TRANSD_DATA_WIDTH * GRADIENT_NUM)];

  // coalesced read (srcGlobalOffset + xid,yid) + padded write to lclArray
  //const int stepsPerWorker = (srcWidth * GRADIENT_NUM) / get_global_size(0); // => globalSizeX must divide 512 (16,32,64,128,256)

  // should be no divergence, whole workgroups take the same path because; 
  // srcWidth and srcHeight must be multiples of TRANSD_DATA_WIDTH = GROUP_SIZE_X = GROUP_SIZE_Y = 16
  if(gx < 0 || gx >= srcWidth || gy < 0 || gy >= srcHeight){
    const int stepsPerWorker = 8;

    for(int i = 0; i < stepsPerWorker; i++){
      lclArray[ly * (TRANSD_DATA_WIDTH * GRADIENT_NUM + lclArrayPadding)      // local Y
                + get_local_size(0) * i + lx] =                               // local X
                                                0;                            // outside border
    }
  }
  else{
    const int stepsPerWorker = 8;

    for(int i = 0; i < stepsPerWorker; i++){
      lclArray[ly * (TRANSD_DATA_WIDTH * GRADIENT_NUM + lclArrayPadding)        // local Y
                + get_local_size(0) * i + lx] =                                 // local X
          srcArray[srcGlobalOffset + gy * srcWidth * GRADIENT_NUM +             // global offset + global Y
            ((gx / get_local_size(0)) * stepsPerWorker + i) * get_local_size(0) // global X
                                               + lx];
    }
  }

  barrier(CLK_LOCAL_MEM_FENCE);

  // non-bank-conflicting (at least attempted) read with transArray as well as coalesced write
  const int pairsPerHalfWarp = transArrayLength / ((get_local_size(0) * get_local_size(1)) / 16);
  const int halfWarps = (get_local_size(1) * get_local_size(0)) / 16;
  const int halfWarpId = (ly * get_local_size(0) + lx) / 16;

  const int blockHeight = get_global_size(1) - 2 * TRANSD_DATA_WIDTH;
  const int topLeftY = (get_group_id(1)-1) * TRANSD_DATA_WIDTH;
  const int topLeftX = (get_group_id(0)-1) * TRANSD_DATA_WIDTH;

  const int dstGroupOffset = (topLeftY * srcWidth + topLeftX) * GRADIENT_NUM * TOTAL_PETALS_NO;

  const int petalStart = ((srcGlobalOffset / (srcWidth * GRADIENT_NUM)) / srcHeight) * REGION_PETALS_NO + (srcGlobalOffset > 0);

  const int offset = (halfWarpId < (transArrayLength % pairsPerHalfWarp) ? halfWarpId : (transArrayLength % pairsPerHalfWarp));
  for(int p = pairsPerHalfWarp * halfWarpId + offset; 
          p < (halfWarpId == halfWarps-1 ? transArrayLength : pairsPerHalfWarp * (halfWarpId+1) + offset + (halfWarpId < transArrayLength % pairsPerHalfWarp)); 
          p++){
    const int fromP1   = transArray[p * 4];
    const int fromP2   = transArray[p * 4 + 1];
    const int toOffset = transArray[p * 4 + 2];
    const int petalNo  = transArray[p * 4 + 3];
    
    const int toOffsetY = floor(toOffset / (float) TRANSD_PAIRS_OFFSET_WIDTH);
    const int toOffsetX = toOffset - toOffsetY * TRANSD_PAIRS_OFFSET_WIDTH - TRANSD_PAIRS_OFFSET_WIDTH/2;

    const int intraHalfWarpOffset = (lx >= 8) * (fromP2-fromP1);

    if(topLeftY+toOffsetY < 0 || topLeftY+toOffsetY >= blockHeight
    || topLeftX+toOffsetX < 0 || topLeftX+toOffsetX >= srcWidth)
    {     }
    else if(fromP2 != TRANSD_PAIRS_SINGLE_ONLY || (lx < 8)){
      dstArray[dstGroupOffset
               + (toOffsetY * srcWidth + toOffsetX) * GRADIENT_NUM * TOTAL_PETALS_NO
               + (petalStart + petalNo) * GRADIENT_NUM + lx] =

        lclArray[((fromP1+intraHalfWarpOffset) / TRANSD_DATA_WIDTH) * (TRANSD_DATA_WIDTH * GRADIENT_NUM + lclArrayPadding) 
               + ((fromP1+intraHalfWarpOffset) % TRANSD_DATA_WIDTH) * GRADIENT_NUM + lx % 8];
    }
  }
}
