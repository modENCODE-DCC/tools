#!/bin/sh

#a little script to process sam files into bam for viewing in samtools tview
#run this like ./process2sam.sh <fasta_file> <sam gzip file>
#be sure that samtools is already installed, and that you add the 
#samtools path in your path, below.


export PATH=/users/nicolew/samtools:$PATH

fasta=$1
sam=$2

#fasta="ex1.fa"
fai="$fasta.fai"
#sam="ex1.sam.gz"
aln_bam="$sam.bam"
aln_sorted="$sam.sorted"

# index the reference FASTA
# samtools faidx ex1.fa                 
echo "indexing the FASTA"
echo `samtools faidx "$fasta"`

# SAM->BAM
# samtools import ex1.fa.fai ex1.sam.gz ex1.bam   
echo "converting SAM->BAM"
echo `samtools import "$fai" "$sam" "$aln_bam"`

# sort the alignment
#samtools sort aln.bam aln.sorted
echo "sorting the alignment"
echo `samtools sort "$aln_bam" "$aln_sorted"`

# index BAM
# samtools index ex1.bam                
echo "indexing BAM file"
echo `samtools index "$aln_sorted".bam`

#echo "pileup alignment"
#echo `samtools pileup -f "$fasta" "$aln_sorted"`

echo "Done."
echo "now you can run: samtools tview $aln_sorted.bam $fasta"