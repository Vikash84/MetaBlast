#
# Copyright 2021 Simone Maestri. All rights reserved.
# Simone Maestri <simone.maestri@univr.it>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

#!/bin/bash


PIPELINE_DIR=$(realpath $( dirname "${BASH_SOURCE[0]}" ))
source $PIPELINE_DIR"/config_MetaBlast.sh"

usage="$(basename "$0") [-f fasta_reads] [-db blast_indexed_database]"

while :
do
    case "$1" in
      -h | --help)
          echo $usage
          exit 0
          ;;
      -f)
          fasta_reads=$(realpath $2)
          shift 2
          echo "Fasta reads: $fasta_reads"
          ;;
      -db)
           blast_db=$2
           shift 2
           echo "Blast indexed db: $blast_db"
           ;;
       --) # End of all options
           shift
           break
           ;;
       -*)
           echo "Error: Unknown option: $1" >&2
           ## or call function display_help
           exit 1
           ;;
        *) # No more options
           break
           ;;
    esac
done


blast_threads=1
#makeblastdb -in $2 -parse_seqids -dbtype nucl
sample_name_tmp=$(basename "$fasta_reads")
sample_name="${sample_name_tmp%.*}"
working_dir=$(dirname "$fasta_reads")
split -l $chunk_size -d $fasta_reads $sample_name".chunk"
parallel_blast=$working_dir"/parallel_blast_"$sample_name".sh"
parallel_filtering=$working_dir"/parallel_filtering_"$sample_name".sh"

for f in $(find $working_dir -maxdepth 1 | grep $sample_name".chunk"); do
  echo "$BLAST -db $blast_db -query $f -num_threads $blast_threads -outfmt \"6 qseqid sgi salltitles length pident qcovs evalue bitscore\" -evalue $max_evalue > $working_dir"/"$(basename $f)_blast_hits.txt" >> $parallel_blast
done
parallel -j $threads < $parallel_blast

for f in $(find $working_dir -maxdepth 1 | grep $sample_name".chunk.*_blast_hits.txt"); do
  echo "$RSCRIPT $PIPELINE_DIR/Filter_Blast_hits.R $f $min_query_cov $min_id_perc" >> $parallel_filtering
done
parallel -j $threads < $parallel_filtering

fil_chunks=$(find $working_dir -maxdepth 1 | grep $sample_name"\.chunk.*_blast_hits_unique_min_id_perc_"$min_id_perc"_min_query_cov_"$min_query_cov"\.txt")
cat $fil_chunks > $working_dir"/"$sample_name"_blast_hits_unique_min_id_perc_"$min_id_perc"_min_query_cov_"$min_query_cov".txt"
cat $working_dir/$sample_name"_blast_hits_unique_min_id_perc_"$min_id_perc"_min_query_cov_"$min_query_cov".txt" | cut -f2 | cut -d' ' -f1 | sort | uniq -c | sort -nr > $working_dir/$sample_name"_blast_hits_counts_no_taxonomy_tmp.txt"
for gb in $(rev $working_dir"/"$sample_name"_blast_hits_counts_no_taxonomy_tmp.txt" | cut -d' ' -f1 | rev); do
  total=$(cat $working_dir"/"$sample_name"_blast_hits_unique_min_id_perc_"$min_id_perc"_min_query_cov_"$min_query_cov".txt" | grep $gb | wc -l);
  pid_tot=$(cat $working_dir"/"$sample_name"_blast_hits_unique_min_id_perc_"$min_id_perc"_min_query_cov_"$min_query_cov".txt" | grep $gb | cut -f5 | paste -sd+ | bc);
  qcov_tot=$(cat $working_dir"/"$sample_name"_blast_hits_unique_min_id_perc_"$min_id_perc"_min_query_cov_"$min_query_cov".txt" | grep $gb | cut -f6 | paste -sd+ | bc);
  pid=$(echo "scale=2;" $pid_tot / $total | bc);
  qcov=$(echo "scale=2;" $qcov_tot / $total | bc) ;
  nr=$(rev $working_dir"/"$sample_name"_blast_hits_counts_no_taxonomy_tmp.txt" | grep $(echo $gb | rev) | cut -d' ' -f2 | rev);
  echo -e $nr"\t"$gb"\t"$pid"\t"$qcov >> $working_dir"/"$sample_name"_blast_hits_counts_no_taxonomy.txt";
done

sed -i "1s/^/Read id\tGenbank id\tSubject description\tAlignment length (bp)\tAlignment identity perc.\tQuery coverage perc.\tE-value\tBitscore\n/" $working_dir"/"$sample_name"_blast_hits_unique_min_id_perc_"$min_id_perc"_min_query_cov_"$min_query_cov".txt"
$RSCRIPT $PIPELINE_DIR"/Retrieve_taxonomy.R" $working_dir/$sample_name"_blast_hits_counts_no_taxonomy.txt" $working_dir/$sample_name"_summary_blast_hits_unique_min_id_perc_"$min_id_perc"_min_query_cov_"$min_query_cov".txt"
tmp=$(find $working_dir -maxdepth 1 | grep -P $sample_name".chunk|_no_taxonomy|parallel_")
rm $tmp
