function results = benchmark_backbones()
%BENCHMARK_BACKBONES  ResNet-50 vs EfficientNet-B0 selection harness.
%
%   results = benchmark_backbones()
%
%   Trains both ImageNet-pretrained backbones on APTOS 2019 and reports the
%   four-axis comparison (docs/ARCHITECTURE.md §3.2, §2 Stage 6 metric):
%     referable SE / SP   (primary target >90% / >85%)
%     AUROC               (referable and multiclass)
%     inference latency   (prototype hardware)
%     model size          (memory/storage for rural deployment)
%
%   Records the chosen backbone + metrics into config/experiment_config.m
%   (cfg.model). The final model is NOT pinned until this runs.
%
%   TODO(Sprint 2+). Sprint 0 refuses to fabricate a backbone decision.

    raiseError('benchmark_backbones', 'NotImplemented', ...
        'Backbone benchmark is a Sprint 2+ task (needs APTOS + DL Toolbox).');
end