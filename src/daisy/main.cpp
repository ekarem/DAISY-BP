#include "main.h"
#include <stdio.h>
#include <sys/time.h>
#include <time.h>

using namespace kutility;

double getStd(double* observations, int length);
double timeDiff(struct timeval start, struct timeval end);

int main( int argc, char **argv  )
{
  int counter = 1;
  struct timeval startTime,endTime;
  int width, height;
  uchar* srcArray = NULL;

  gettimeofday(&startTime,NULL);

  char* filename = NULL;

  // Get command line options
  if(argc > counter+1 && (!strcmp("-i", argv[counter]) || !strcmp("--image", argv[counter]))){

    filename = argv[++counter];
    load_gray_image (filename, srcArray, height, width);
    printf("HxW=%dx%d\n",height, width);
    counter++;
    
    ocl_constructs * daisyCl = newOclConstructs(0,0,0);
    ocl_daisy_programs * daisyPrograms = (ocl_daisy_programs*)malloc(sizeof(ocl_daisy_programs));

    float sigmas[3] = {2.5,5,7.5};
    daisy_params * daisy = newDaisyParams(srcArray, height, width, 8, 8, 3);//, sigmas);

    double start,end,diff;

    time_params times;
    times.measureDeviceHostTransfers = 1;

    initOcl(daisyPrograms,daisyCl);

    daisy->oclPrograms = *daisyPrograms;

    oclDaisy(daisy, daisyCl, &times);

    //printf("Paired Offsets: %d\n",pairedOffsetsLength);
    //printf("Actual Pairs: %d\n",actualPairs);

    string binaryfile = filename;
    binaryfile += ".bdaisy";
    kutility::save_binary(binaryfile, daisy->descriptors, daisy->paddedHeight * daisy->paddedWidth, daisy->descriptorLength, 1, kutility::TYPE_FLOAT);

    gettimeofday(&endTime,NULL);

    free(daisy->array);
    printf("padded dimensions: %dx%d\n",daisy->paddedHeight,daisy->paddedWidth);
    start = startTime.tv_sec+(startTime.tv_usec/1000000.0);
    end = endTime.tv_sec+(endTime.tv_usec/1000000.0);
    diff = end-start;
    printf("\nMain: %.3fs\n",diff);
  }
  else if(0){
    
    // do the profiling across a range of inputs from 128x128 to 1536x1536

    // initialise all the opencl stuff first outside loop
    daisy_params * daisy;
    ocl_daisy_programs * daisyPrograms = (ocl_daisy_programs*)malloc(sizeof(ocl_daisy_programs));

    ocl_constructs * daisyCl = newOclConstructs(0,0,0);

    initOcl(daisyPrograms,daisyCl);

    // initialise loop variables, input range numbers etc..
    struct tm * sysTime = NULL;                     

    time_t timeVal = 0;                            
    timeVal = time(NULL);                          
    sysTime = localtime(&timeVal);

    char * csvOutName = (char*)malloc(sizeof(char) * 500);
    sprintf(csvOutName, "gdaisy-speed-tests-%02d%02d-%02d%02d.csv", sysTime->tm_mon+1, sysTime->tm_mday, sysTime->tm_hour, sysTime->tm_min);

    FILE * csvOut = fopen(csvOutName,"w");

    /* Standard ranges QVGA,VGA,SVGA,XGA,SXGA,SXGA+,UXGA,QXGA*/
    int heights[8] = {320,640,800,1024,1280,1400,1600,2048};
    int widths[8] = {240,480,600,768,1024,1050,1200,1536};
    int total = 8;

    /* Without transfer ranges */
    /*int heights[12] = {128,256,384,512,640,768,896,1024,1152,1280,1408,1536};
    int widths[12] = {128,256,384,512,640,768,896,1024,1152,1280,1408,1536};
    int total = 12;*/
    
    /* With transfer ranges */
    /*int heights[4] = {128,256,384,512};//,640,768,896,1024,1152,1280,1408,1536};
    int widths[4] = {128,256,384,512};//,640,768,896,1024,1152,1280,1408,1536};
    int total = 4;//12;*/

    // allocate the memory
    unsigned char * array = (unsigned char *)malloc(sizeof(unsigned char) * heights[total-1] * widths[total-1]);

    // generate random value input
    for(int i = 0; i < heights[total-1]*widths[total-1]; i++)
      array[i] = i % 255;

    fprintf(csvOut,"height,width,convgrad,transA,transB,transBhost,whole,wholestd,dataTransfer,iterations,success\n");

    char* templateRow = "%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%d,%d\n";

    for(int w = 0; w < total; w++){

      int width = widths[w];
      int height = heights[w];

      printf("%dx%d\n",height,width);

      int iterations = 25;
      int success = 0;
      double * wholeTimes = (double*)malloc(sizeof(double) * iterations);

      time_params times;

      double t_convGrad = 0;
      double t_transA = 0;
      double t_transB = 0;
      double t_transBhost = 0;
      double t_whole = 0;

      times.measureDeviceHostTransfers = 0;

      daisy = newDaisyParams(array, height, width, 8, 8, 3);//, NULL);
      daisy->oclPrograms = *daisyPrograms;

      for(int i = 0; i < iterations; i++){
      
        success |= oclDaisy(daisy, daisyCl, &times);

        t_convGrad += timeDiff(times.startConvGrad, times.endConvGrad);
        t_transA   += timeDiff(times.startTransGrad, times.endTransGrad);
        if(times.measureDeviceHostTransfers)
          t_transBhost += timeDiff(times.startTransDaisy, times.endTransDaisy);
        else
          t_transB += timeDiff(times.startTransDaisy, times.endTransDaisy);

        wholeTimes[i] = timeDiff(times.startFull, times.endFull);
        t_whole += wholeTimes[i];

      }

      t_convGrad    /= iterations;
      t_transA      /= iterations;
      t_transBhost  /= iterations;
      t_transB      /= iterations;
      t_whole       /= iterations;

      double wholeStd = getStd(wholeTimes,iterations);

      fprintf(csvOut, templateRow, height, width, t_convGrad, t_transA, t_transB, t_transBhost, t_whole, wholeStd,
                      times.measureDeviceHostTransfers, iterations, success);

    }
    
    // print name of output file
    fclose(csvOut);
    printf("Speed test results written to %s.\n", csvOutName);
    free(daisy->descriptors);
    free(array);
  }
  else{
    fprintf(stderr,"Pass image filename with argument -i <file>\n");
    return 1;
  }

  return 0;
}

double timeDiff(struct timeval start, struct timeval end){

  return (end.tv_sec+(end.tv_usec/1000000.0)) - (start.tv_sec+(start.tv_usec/1000000.0));

}

double getStd(double * observations, int length){

  double mean = .0f;
  for(int i = 0; i < length; i++)
    mean += observations[i];
  mean /= length;
  double stdSum = .0f;
  for(int i = 0; i < length; i++)
    stdSum += pow(observations[i] - mean,2);

  return sqrt(stdSum / length);

}
