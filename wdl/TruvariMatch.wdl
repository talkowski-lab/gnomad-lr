version 1.0

import "Structs.wdl"

workflow TruvariMatch {
    input {
        File vcf_eval_unmatched
        File vcf_eval_unmatched_index
        File vcf_truth
        File vcf_truth_index
        File ref_fasta
        File ref_fasta_fai
        String prefix
        String pipeline_docker
        RuntimeAttr? runtime_attr_override
    }

    call FilterTruthVcf {
        input:
            vcf_truth = vcf_truth,
            vcf_truth_index = vcf_truth_index,
            prefix = prefix,
            pipeline_docker = pipeline_docker,
            runtime_attr_override = runtime_attr_override
    }

    # Pass 1: pctseq = 0.9
    call RunTruvari as RunTruvari_09 {
        input:
            vcf_eval = vcf_eval_unmatched,
            vcf_eval_index = vcf_eval_unmatched_index,
            vcf_truth_filtered = FilterTruthVcf.filtered_vcf,
            vcf_truth_filtered_index = FilterTruthVcf.filtered_vcf_index,
            ref_fasta = ref_fasta,
            ref_fasta_fai = ref_fasta_fai,
            pctseq = 0.9,
            prefix = "~{prefix}.0.9",
            pipeline_docker = pipeline_docker,
            runtime_attr_override = runtime_attr_override
    }

    call AnnotateVcf as AnnotateMatched_09 {
        input:
            vcf_in = RunTruvari_09.matched_vcf,
            vcf_in_index = RunTruvari_09.matched_vcf_index,
            vcf_out_name = "~{prefix}.0.9.annotated.vcf.gz",
            tag_name = "gnomAD_V4_match",
            tag_value = "TRUVARI_0.9",
            pipeline_docker = pipeline_docker,
            runtime_attr_override = runtime_attr_override
    }

    # Pass 2: pctseq = 0.7
    call RunTruvari as RunTruvari_07 {
        input:
            vcf_eval = RunTruvari_09.unmatched_vcf,
            vcf_eval_index = RunTruvari_09.unmatched_vcf_index,
            vcf_truth_filtered = FilterTruthVcf.filtered_vcf,
            vcf_truth_filtered_index = FilterTruthVcf.filtered_vcf_index,
            ref_fasta = ref_fasta,
            ref_fasta_fai = ref_fasta_fai,
            pctseq = 0.7,
            prefix = "~{prefix}.0.7",
            pipeline_docker = pipeline_docker,
            runtime_attr_override = runtime_attr_override
    }

    call AnnotateVcf as AnnotateMatched_07 {
        input:
            vcf_in = RunTruvari_07.matched_vcf,
            vcf_in_index = RunTruvari_07.matched_vcf_index,
            vcf_out_name = "~{prefix}.0.7.annotated.vcf.gz",
            tag_name = "gnomAD_V4_match",
            tag_value = "TRUVARI_0.7",
            pipeline_docker = pipeline_docker,
            runtime_attr_override = runtime_attr_override
    }

    # Pass 3: pctseq = 0.5
    call RunTruvari as RunTruvari_05 {
        input:
            vcf_eval = RunTruvari_07.unmatched_vcf,
            vcf_eval_index = RunTruvari_07.unmatched_vcf_index,
            vcf_truth_filtered = FilterTruthVcf.filtered_vcf,
            vcf_truth_filtered_index = FilterTruthVcf.filtered_vcf_index,
            ref_fasta = ref_fasta,
            ref_fasta_fai = ref_fasta_fai,
            pctseq = 0.5,
            prefix = "~{prefix}.0.5",
            pipeline_docker = pipeline_docker,
            runtime_attr_override = runtime_attr_override
    }

    call AnnotateVcf as AnnotateMatched_05 {
        input:
            vcf_in = RunTruvari_05.matched_vcf,
            vcf_in_index = RunTruvari_05.matched_vcf_index,
            vcf_out_name = "~{prefix}.0.5.annotated.vcf.gz",
            tag_name = "gnomAD_V4_match",
            tag_value = "TRUVARI_0.5",
            pipeline_docker = pipeline_docker,
            runtime_attr_override = runtime_attr_override
    }

    call ConcatTruvariResults as ConcatMatched {
        input:
            vcfs = [AnnotateMatched_09.vcf_out, AnnotateMatched_07.vcf_out, AnnotateMatched_05.vcf_out],
            vcfs_idx = [AnnotateMatched_09.vcf_out_index, AnnotateMatched_07.vcf_out_index, AnnotateMatched_05.vcf_out_index],
            outfile_prefix = "~{prefix}.truvari_matched.combined",
            pipeline_docker = pipeline_docker,
            runtime_attr_override = runtime_attr_override
    }

    output {
        File matched_vcf = ConcatMatched.concat_vcf
        File matched_vcf_index = ConcatMatched.concat_vcf_idx
        File unmatched_vcf = RunTruvari_05.unmatched_vcf
        File unmatched_vcf_index = RunTruvari_05.unmatched_vcf_index
    }
}

task FilterTruthVcf {
    input {
        File vcf_truth
        File vcf_truth_index
        String prefix
        String pipeline_docker
        RuntimeAttr? runtime_attr_override
    }
    command <<<
        set -euxo pipefail
        bcftools view -e 'INFO/variant_type="snv"' -Oz -o ~{prefix}.truth.non_snv.vcf.gz ~{vcf_truth}
        tabix -p vcf -f ~{prefix}.truth.non_snv.vcf.gz
    >>>
    output {
        File filtered_vcf = "~{prefix}.truth.non_snv.vcf.gz"
        File filtered_vcf_index = "~{prefix}.truth.non_snv.vcf.gz.tbi"
    }
    RuntimeAttr default_attr = object {
        cpu_cores: 1, mem_gb: 4, disk_gb: ceil(size(vcf_truth, "GB")) * 2 + 5,
        boot_disk_gb: 10, preemptible_tries: 2, max_retries: 1
    }
    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
    runtime {
        cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
        memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
        disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
        bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
        docker: pipeline_docker
        preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
        maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
    }
}

task RunTruvari {
    input {
        File vcf_eval
        File vcf_eval_index
        File vcf_truth_filtered
        File vcf_truth_filtered_index
        File ref_fasta
        File ref_fasta_fai
        Float pctseq
        String prefix
        String pipeline_docker
        RuntimeAttr? runtime_attr_override
    }
    command <<<
        set -euxo pipefail

        if [ -d "~{prefix}_truvari" ]; then
            rm -r "~{prefix}_truvari"
        fi
        
        truvari bench \
            -b ~{vcf_truth_filtered} \
            -c ~{vcf_eval} \
            -o "~{prefix}_truvari" \
            --reference ~{ref_fasta} \
            --pctseq ~{pctseq} \
            --sizemin 5 \
            --sizefilt 10
        
        tabix -p vcf -f ~{prefix}_truvari/tp-comp.vcf.gz
        tabix -p vcf -f ~{prefix}_truvari/fn.vcf.gz
    >>>
    output {
        File matched_vcf = "~{prefix}_truvari/tp-comp.vcf.gz"
        File matched_vcf_index = "~{prefix}_truvari/tp-comp.vcf.gz.tbi"
        File unmatched_vcf = "~{prefix}_truvari/fn.vcf.gz"
        File unmatched_vcf_index = "~{prefix}_truvari/fn.vcf.gz.tbi"
    }
    RuntimeAttr default_attr = object {
        cpu_cores: 1, mem_gb: 8, disk_gb: ceil(size(vcf_eval, "GB") + size(vcf_truth_filtered, "GB")) * 5 + 20,
        boot_disk_gb: 10, preemptible_tries: 2, max_retries: 1
    }
    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
    runtime {
        cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
        memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
        disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
        bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
        docker: pipeline_docker
        preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
        maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
    }
}

task AnnotateVcf {
    input {
        File vcf_in
        File vcf_in_index
        String vcf_out_name
        String tag_name
        String tag_value
        String pipeline_docker
        RuntimeAttr? runtime_attr_override
    }
    command <<<
        set -euxo pipefail
        
        # Create a temporary header file with the new INFO tag definition
        echo '##INFO=<ID=~{tag_name},Number=1,Type=String,Description="Matching status against gnomAD v4.">' > header.hdr

        # Create a temporary annotation file from the input vcf
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t~{tag_value}\n' ~{vcf_in} | bgzip -c > annots.tab.gz
        tabix -s 1 -b 2 -e 2 annots.tab.gz

        # Annotate the VCF
        bcftools annotate \
            -a annots.tab.gz \
            -h header.hdr \
            -c CHROM,POS,REF,ALT,~{tag_name} \
            -Oz -o ~{vcf_out_name} \
            ~{vcf_in}
        
        tabix -p vcf -f ~{vcf_out_name}
    >>>
    output {
        File vcf_out = "~{vcf_out_name}"
        File vcf_out_index = "~{vcf_out_name}.tbi"
    }
    RuntimeAttr default_attr = object {
        cpu_cores: 1, mem_gb: 4, disk_gb: ceil(size(vcf_in, "GB")) * 2 + 5,
        boot_disk_gb: 10, preemptible_tries: 2, max_retries: 1
    }
    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
    runtime {
        cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
        memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
        disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
        bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
        docker: pipeline_docker
        preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
        maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
    }
}

task ConcatTruvariResults {
    input {
        Array[File] vcfs
        Array[File] vcfs_idx
        String outfile_prefix
        String pipeline_docker
        RuntimeAttr? runtime_attr_override
    }
    command <<<
        set -euxo pipefail
        bcftools concat -a -Oz -o ~{outfile_prefix}.vcf.gz ~{sep=' ' vcfs}
        tabix -p vcf -f ~{outfile_prefix}.vcf.gz
    >>>
    output {
        File concat_vcf = "~{outfile_prefix}.vcf.gz"
        File concat_vcf_idx = "~{outfile_prefix}.vcf.gz.tbi"
    }
     RuntimeAttr default_attr = object {
        cpu_cores: 1, mem_gb: 4, disk_gb: ceil(size(vcfs, "GB")) * 2 + 5,
        boot_disk_gb: 10, preemptible_tries: 2, max_retries: 1
    }
    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
    runtime {
        cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
        memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
        disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
        bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
        docker: pipeline_docker
        preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
        maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
    }
} 