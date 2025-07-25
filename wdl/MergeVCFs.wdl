version 1.0

import "Structs.wdl"

workflow MergeVCFs {
    input {
        Array[File] vcf_files
        String sv_base_mini_docker
        String cohort_prefix
        Boolean sort_after_merge
    }

    call CombineVCFs {
        input:
        vcf_files=vcf_files,
        sv_base_mini_docker=sv_base_mini_docker,
        cohort_prefix=cohort_prefix,
        sort_after_merge=sort_after_merge
    }

    output {
        File merged_vcf_file = CombineVCFs.merged_vcf_file
        File merged_vcf_idx = CombineVCFs.merged_vcf_idx
    }
}

task CombineVCFSamples {
    input {
        Array[File] vcf_files
        String merged_filename
        String sv_base_mini_docker
        RuntimeAttr? runtime_attr_override
    }

    Float input_size = size(vcf_files, "GB")
    Float base_disk_gb = 10.0
    Float input_disk_scale = 5.0

    RuntimeAttr runtime_default = object {
        mem_gb: 4,
        disk_gb: ceil(base_disk_gb + input_size * input_disk_scale),
        cpu_cores: 1,
        preemptible_tries: 3,
        max_retries: 1,
        boot_disk_gb: 10
    }

    RuntimeAttr runtime_override = select_first([runtime_attr_override, runtime_default])
    
    runtime {
        memory: "~{select_first([runtime_override.mem_gb, runtime_default.mem_gb])} GB"
        disks: "local-disk ~{select_first([runtime_override.disk_gb, runtime_default.disk_gb])} HDD"
        cpu: select_first([runtime_override.cpu_cores, runtime_default.cpu_cores])
        preemptible: select_first([runtime_override.preemptible_tries, runtime_default.preemptible_tries])
        maxRetries: select_first([runtime_override.max_retries, runtime_default.max_retries])
        docker: sv_base_mini_docker
        bootDiskSizeGb: select_first([runtime_override.boot_disk_gb, runtime_default.boot_disk_gb])
    }

    command <<<
        set -euo pipefail
        VCFS="~{write_lines(vcf_files)}"
        cat $VCFS | awk -F '/' '{print $NF"\t"$0}' | sort -k1,1V | awk '{print $2}' > vcfs_sorted.list
        for vcf in $(cat vcfs_sorted.list);
        do
            bcftools annotate -x ^FORMAT/GT,FORMAT/AD,FORMAT/DP,FORMAT/GQ,FORMAT/PL -Oz -o "$vcf"_stripped.vcf.gz $vcf
            tabix "$vcf"_stripped.vcf.gz
            echo "$vcf"_stripped.vcf.gz >> vcfs_sorted_stripped.list
        done
        bcftools merge -m none --force-samples --no-version -Oz --file-list vcfs_sorted_stripped.list --output ~{merged_filename}_merged.vcf.gz
            >>>

    output {
        File merged_vcf_file = "~{merged_filename}_merged.vcf.gz"
    }
}

task CombineVCFs {
    input {
        Array[File] vcf_files
        String sv_base_mini_docker
        String cohort_prefix
        Boolean sort_after_merge
        Boolean naive=true
        Boolean allow_overlaps=false  # cannot be used with naive
        Array[File]? vcf_indices  # need if allow_overlaps=true
        RuntimeAttr? runtime_attr_override
    }

    #  generally assume working disk size is ~2 * inputs, and outputs are ~2 *inputs, and inputs are not removed
    #  generally assume working memory is ~3 * inputs
    #  CleanVcf5.FindRedundantMultiallelics
    Float input_size = size(vcf_files, "GB")
    Float base_disk_gb = 10.0
    Float input_disk_scale = if !sort_after_merge then 5.0 else 20.0
    
    RuntimeAttr runtime_default = object {
        mem_gb: 4,
        disk_gb: ceil(base_disk_gb + input_size * input_disk_scale),
        cpu_cores: 1,
        preemptible_tries: 3,
        max_retries: 1,
        boot_disk_gb: 10
    }

    RuntimeAttr runtime_override = select_first([runtime_attr_override, runtime_default])

    runtime {
        memory: "~{select_first([runtime_override.mem_gb, runtime_default.mem_gb])} GB"
        disks: "local-disk ~{select_first([runtime_override.disk_gb, runtime_default.disk_gb])} HDD"
        cpu: select_first([runtime_override.cpu_cores, runtime_default.cpu_cores])
        preemptible: select_first([runtime_override.preemptible_tries, runtime_default.preemptible_tries])
        maxRetries: select_first([runtime_override.max_retries, runtime_default.max_retries])
        docker: sv_base_mini_docker
        bootDiskSizeGb: select_first([runtime_override.boot_disk_gb, runtime_default.boot_disk_gb])
    }

    String merged_vcf_name="~{cohort_prefix}.merged.vcf.gz"
    String sorted_vcf_name="~{cohort_prefix}.merged.sorted.vcf.gz"
    String naive_str = if naive then '-n' else ''
    String overlap_str = if allow_overlaps then '-a' else ''

    command <<<
        set -euo pipefail
        VCFS="~{write_lines(vcf_files)}"
        cat $VCFS | awk -F '/' '{print $NF"\t"$0}' | sort -k1,1V | awk '{print $2}' > vcfs_sorted.list
        bcftools concat ~{naive_str} ~{overlap_str} --no-version -Oz --file-list vcfs_sorted.list --output ~{merged_vcf_name}
        if [ "~{sort_after_merge}" = "true" ]; then
            mkdir -p tmp
            bcftools sort ~{merged_vcf_name} -Oz --output ~{sorted_vcf_name} -T tmp/
            # cat ~{merged_vcf_name} | zcat | awk '$1 ~ /^#/ {print $0;next} {print $0 | "sort -k1,1V -k2,2n"}' > ~{basename(sorted_vcf_name, '.gz')}
            # bgzip ~{basename(sorted_vcf_name, '.gz')}
            tabix ~{sorted_vcf_name}
        else 
            tabix ~{merged_vcf_name}
        fi

    >>>

    output {
        File merged_vcf_file = if sort_after_merge then sorted_vcf_name else merged_vcf_name
        File merged_vcf_idx = if sort_after_merge then sorted_vcf_name + ".tbi" else merged_vcf_name + ".tbi"
    }
}