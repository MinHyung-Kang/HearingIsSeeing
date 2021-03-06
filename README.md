
# Seeing is Hearing

## Basic Information
- Authors : Min Hyung (Daniel) Kang & Chris Kymn
- Course : CS89 - Deep Learning
- Professor : Lorenzo Torresani

In this README, we describe the overall structure of this directory.
For more specific instructions for how to run the code, find README in each directory.


## Directory Structure

### Code
Includes our main training and generating code for Audio2image, Wasserstein GAN, and Soundnet. 
- Audio2Image was adapted from code of Text2Image (https://github.com/reedscot/icml2016)
- SoundNet was adapated from : (https://github.com/cvondrick/soundnet)
- Wasserstein GAN code was adapted from : (https://github.com/fonfonx/WassersteinGAN.torch)

### Data
Includes the smallest dataset we used. For UCF-101 dataset, we include subsampled data from 3 classes.
- ucf3audio_subset : t7 files which include audio features extracted from 3 classes of videos of UCF-101 dataset and the name of the corresponding image
- ucf3_subset : png image files which were collected from 3 classes of videos of UCF101 dataset, after manual cropping of size 200 by 190
- ppmi : 400 image files of people either holding or playing cello. Used to train Wasserstein GAN code.

### DataProcessing
	Includes MATLAB code that performs audio and frame extraction from video, PCA exploration, and dataset generation.


## Prerequisites
###Network Training
- Torch 
- CuDNN 
- Display (https://github.com/szym/display) [Audio2Image]
- Torch 7 Audio (https://github.com/soumith/lua---audio) [SoundNet]
- Torch 7 hdf5 (https://github.com/deepmind/torch-hdf5) [SoundNet]

### Data Processing
- Matlab 