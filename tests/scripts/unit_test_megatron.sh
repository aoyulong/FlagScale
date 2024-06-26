if [ -z "$1" ]
then
  code_id=0
else
  code_id=$1
fi

cd megatron

export PYTHONPATH=..:$PYTHONPATH

torchrun --nproc_per_node=8 -m pytest --import-mode=importlib --cov-append --cov-report=html:/workspace/report/$code_id/cov-report-megatron --cov=megatron/core -q -x tests/unit_tests/data
torchrun --nproc_per_node=8 -m pytest --import-mode=importlib --cov-append --cov-report=html:/workspace/report/$code_id/cov-report-megatron --cov=megatron/core -q -x tests/unit_tests/dist_checkpointing
torchrun --nproc_per_node=8 -m pytest --import-mode=importlib --cov-append --cov-report=html:/workspace/report/$code_id/cov-report-megatron --cov=megatron/core -q -x tests/unit_tests/fusions
torchrun --nproc_per_node=8 -m pytest --import-mode=importlib --cov-append --cov-report=html:/workspace/report/$code_id/cov-report-megatron --cov=megatron/core -q -x tests/unit_tests/models
torchrun --nproc_per_node=8 -m pytest --import-mode=importlib --cov-append --cov-report=html:/workspace/report/$code_id/cov-report-megatron --cov=megatron/core -q -x tests/unit_tests/pipeline_parallel
torchrun --nproc_per_node=8 -m pytest --import-mode=importlib --cov-append --cov-report=html:/workspace/report/$code_id/cov-report-megatron --cov=megatron/core -q -x tests/unit_tests/tensor_parallel
torchrun --nproc_per_node=8 -m pytest --import-mode=importlib --cov-append --cov-report=html:/workspace/report/$code_id/cov-report-megatron --cov=megatron/core -q -x tests/unit_tests/transformer 
torchrun --nproc_per_node=8 -m pytest --import-mode=importlib --cov-append --cov-report=html:/workspace/report/$code_id/cov-report-megatron --cov=megatron/core -q -x tests/unit_tests/*.py 