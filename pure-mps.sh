#!/bin/bash
# Demonstrator script to run multiple simulations per GPU with MPS on DGX-A100
#
# Alan Gray, NVIDIA
# Location of GROMACS binary
NSYS=/usr/local/cuda-11.2/bin/nsys
GMX=/usr/local/gromacs/bin/gmx
# Location of input file
INPUT=/home/cc/simulations/GROMACS_heterogeneous_parallelization_benchmark_info_and_systems_JCP/adh_dodec/topol.tpr

NGPU=1 # Number of GPUs in server
NCORE=128 # Number of CPU cores in server

# NSIMPERGPU=16 # Number of simulations to run per GPU (with MPS)

for ng in 16 # 1,2,4,8,16,32
do
    NSIMPERGPU=$ng
    for nt in 4 # 1,2,4,8,16,32
    do
        # Number of threads per simulation
        NCPU=$(($nt*($NGPU*$NSIMPERGPU)))
        echo "NCPU = $NCPU"
        if [ $NCPU -gt 128 ]
        then
            echo "Setting NCPU to 128"
            NCPU=128
        fi
        export OMP_NUM_THREADS=$NCPU

        # Start MPS daemon
        sudo -E nvidia-cuda-mps-control -d

        # Loop over number of GPUs in server
        for (( i=0; i<$NGPU; i++ ));
        do
            # Set a CPU NUMA specific to GPU in use with best affinity (specific to DGX-A100)
            case $i in
                0)NUMA=1;;
            esac

            # Loop over number of simulations per GPU
            for (( j=0; j<$NSIMPERGPU; j++ ));
            do
                # Create a unique identifier for this simulation to use as a working directory
                id=gpu${i}_sim${j}
                rm -rf $id
                mkdir -p $id
                cd $id

                ln -s $INPUT topol.tpr

                # Launch GROMACS in the background on the desired resources with Nsight Systems profiling enabled
                echo "Launching simulation $j on GPU $i with $NTHREAD CPU thread(s) on NUMA region $NUMA"
                sudo -E numactl --cpunodebind=$NUMA $NSYS profile -t cuda,nvtx --stats=true --force-overwrite=true \
                --output="profile_${ng}_${nt}" --delay=10 --event-sampling-frequency=1 --gpu-metrics-frequency=1000 --sampling-frequency=101 \
                $GMX mdrun -update gpu -ntmpi 1 -nsteps 20000 -maxh 1.0 -append -resetstep 19000 -nstlist 400 \
                -nb gpu -bonded gpu -pme gpu > mdrun.log 2>&1 &
                cd ..
            done
        done
        echo "Waiting for simulations to complete..."
        wait

        # Merge the profiles for all simulations
        dir_name=MPS${ng}_${nt}
        mkdir -p $dir_name
        $NSYS stats -d $dir_name -o "$dir_name/merged_report" profile_${ng}_${nt}*
        sudo rm profile_${ng}_${nt}*
    done
done

sudo ./stop-mps.sh
