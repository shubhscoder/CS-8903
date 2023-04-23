mkdir simulations
scp gromacs-2023.1.tar.gz cc@192.5.87.22:/home/cc/simulations/
cd simulations

tar xfz gromacs-2023.1.tar.gz
cd gromacs-2023.1
mkdir build
cd build

sudo snap install cmake --classic
cmake .. -DGMX_BUILD_OWN_FFTW=ON -DGMX_GPU=CUDA

make -j128

sudo make install

source /usr/local/gromacs/bin/GMXRC

sudo apt-get update
sudo apt-get install numactl

nsys start --stop-on-exit=false

nsys profile --trace=cuda,cublas,cudnn,nvtx,opengl,openacc,openmp,mpi,osrt --cuda-memory-usage=true --stats=true ./pure-mps.sh

nsys-stop

nvidia-smi | grep 'gmx' | awk '{ print $5 }' | sudo xargs -n1 kill -9


nsys profile -t cuda,nvtx -f true -o all --stats=true --trace-fork-before-exec=true bash -c "./pure-mps.sh"

