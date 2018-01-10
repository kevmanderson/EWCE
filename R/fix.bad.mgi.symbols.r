#' fix.bad.mgi.symbols
#' - Given an expression matrix, wherein the rows are supposed to be MGI symbols, find those symbols which are not official MGI symbols, then
#' check in the MGI synonm database for whether they match to a proper MGI symbol. Where a symbol is found to be an aliases for a gene that is already
#' in the dataset, the combined reads are summed together.
#'
#' Also checks whether any gene names contain "Sep", "Mar" or "Feb". These should be checked for any suggestion that excel has corrupted the gene names.
#' @param exp An expression matrix where the rows are MGI symbols
#' @param mrk_file_path Path to the MRK_List2 file which can be downloaded from www.informatics.jax.org/downloads/reports/index.html
#' @param printAllBadSymbols Output to console all the bad gene symbols
#' @return Returns the expression matrix with the rownames corrected and rows representing the same gene merged
#' @examples
#' \dontrun{
#' # Load the single cell data
#' data("cortex_mrna")
#' cortex_mrna$exp = fix.bad.mgi.symbols(cortex_mrna$exp)
#' }
#' @export
#' @import biomaRt
fix.bad.mgi.symbols <- function(exp,mrk_file_path=NULL,printAllBadSymbols=FALSE){
    # Check arguments
    if(is.null(exp)){stop("ERROR: 'exp' is null. It should be a numerical matrix with the rownames being MGI symbols.")}
    if(!is.null(levels(exp[1,3]))){stop("ERROR: Input 'exp' should not contain factors. Perhaps stringsAsFactors was not set while loading")}
    if(class(exp[1,3])=="character"){
        print("Warning: Input 'exp' stored as characters. Converting to numeric. Check that it looks correct.")
        exp = as.matrix(exp)
        storage.mode(exp) <- "numeric"
    }
    # Check that exp is not some wierd input format like those generated by readr functions
    if(!class(exp)[1] %in% c("matrix","data.frame")){
        stop("ERROR: exp must be either matrix or data.frame")
    }

    # Check for symbols which are not real MGI symbols
    #library("biomaRt")
    #mouse = useMart(host="www.ensembl.org", "ENSEMBL_MART_ENSEMBL", dataset = "mmusculus_gene_ensembl")
    #attrib_mus = listAttributes(mouse)
    #mgi_symbols = getBM(attributes=c("mgi_symbol","ensembl_gene_id"), mart=mouse)
    data(all_mgi)
    not_MGI = rownames(exp)[!rownames(exp) %in% all_mgi]
    print(sprintf("%s rows do not have proper MGI symbols",length(not_MGI)))
    if(length(not_MGI)>20){print(not_MGI[1:20])}

    # Checking for presence of bad date genes, i.e. Sept2 --> 02.Sep
    date_like = not_MGI[grep("Sep|Mar|Feb",not_MGI)]
    if(length(date_like)>0){
        warning(sprintf("Possible presence of excel corrupted date-like genes: %s",paste(date_like,collapse=", ")))
    }

    # Load data from MGI to check for synonyms
    if(is.null(mrk_file_path)){
        data("mgi_synonym_data")
        mgi_data = mgi_synonym_data
    }else{
        if(!file.exists(mrk_file_path)){
            stop("ERROR: the file path used in mrk_file_path does not direct to a real file. Either leave this argument blank or direct to an MRK_List2.rpt file downloaded from the MGI website. It should be possible to obtain from: http://www.informatics.jax.org/downloads/reports/MRK_List2.rpt")
        }
        mgi_data = read.csv(mrk_file_path,sep="\t",stringsAsFactors = FALSE)
        if(!"Marker.Synonyms..pipe.separated." %in% colnames(mgi_synonym_data)){
            stop("ERROR: the MRK_List2.rpt file does not seem to have a column named 'Marker.Synonyms..pipe.separated.'")
        }
        # -- the above file is downlaoded from: http://www.informatics.jax.org/downloads/reports/index.html
        mgi_data = mgi_data[!mgi_data$Marker.Synonyms..pipe.separated.=="",]
    }

    # If there are too many genes in not_MGI then the grep crashes... so try seperately
    stepSize=500
    if(length(not_MGI)>stepSize){
        lower=1
        upper=stepSize
        for(i in 1:ceiling(length(not_MGI)/stepSize)){
            if(upper>length(not_MGI)){upper=length(not_MGI)}
            use_MGI = not_MGI[lower:upper]
            tmp = grep(paste(use_MGI,collapse = ("|")),mgi_data$Marker.Synonyms..pipe.separated.)
            if(i==1){ keep_rows = tmp }else{ keep_rows = c(keep_rows,tmp) }
            lower=lower+stepSize
            upper=upper+stepSize
        }
    }else{
        keep_rows = grep(paste(not_MGI,collapse = ("|")),mgi_data$Marker.Synonyms..pipe.separated.)
    }
    countBottom=countTop=0
    # Count how many "|" symbols are in "mgi_data$Marker.Synonyms..pipe.separated" to determine how many rows the dataframe needs
    #library(stringr)
    allSYN=matrix("",nrow=length(keep_rows)+sum(str_count(mgi_data$Marker.Synonyms..pipe.separated.,"\\|")),ncol=2)
    colnames(allSYN) = c("mgi_symbol","syn")
    for(i in keep_rows){
        #if(i %% 100 == 0){print(i)}
        tmp = data.frame(mgi_symbol=mgi_data[i,]$Marker.Symbol,syn=unlist(strsplit(mgi_data$Marker.Synonyms..pipe.separated.[i],"\\|")),stringsAsFactors = FALSE)
        countBottom=countTop+1
        countTop=countBottom+dim(tmp)[1]-1
        allSYN[countBottom:countTop,1]=tmp[,1]
        allSYN[countBottom:countTop,2]=tmp[,2]
    }
    allSYN = data.frame(allSYN)
    matchingSYN = allSYN[allSYN$syn %in% not_MGI,]
    matchingSYN = matchingSYN[!duplicated(matchingSYN$syn),]
    matchingSYN = matchingSYN[as.character(matchingSYN$mgi_symbol)!=as.character(matchingSYN$syn),]
    rownames(matchingSYN) = matchingSYN$syn

    # Check for duplicates of existing genes
    dupGENES = as.character(matchingSYN$mgi_symbol[matchingSYN$mgi_symbol %in% rownames(exp)])
    print(sprintf("%s poorly annotated genes are replicates of existing genes. These are: ",length(unique(dupGENES))))
    print(unique(dupGENES))

    # Replace mis-used synonyms from the expression data
    exp_Good = exp[!rownames(exp) %in% as.character(matchingSYN$syn),]
    exp_Bad  = exp[as.character(matchingSYN$syn),]

    # Where duplicates exist, sum them together
    for(dG in unique(dupGENES)){
        exp_Good[rownames(exp_Good)==dG,] = apply(rbind(exp_Good[rownames(exp_Good)==dG,],exp_Bad[as.character(matchingSYN$mgi_symbol)==dG,]),2,sum)
    }
    exp_Bad = exp_Bad[!as.character(matchingSYN$mgi_symbol)%in%dupGENES,]
    matchingSYN_deDup = matchingSYN[!as.character(matchingSYN$mgi_symbol)%in%dupGENES,]
    dropDuplicatedMislabelled = as.character(matchingSYN_deDup$syn[duplicated(matchingSYN_deDup$mgi_symbol)])
    matchingSYN_deDup = matchingSYN_deDup[!matchingSYN_deDup$syn %in% dropDuplicatedMislabelled,]
    exp_Bad = exp_Bad[!rownames(exp_Bad) %in% dropDuplicatedMislabelled,]
    rownames(exp_Bad)=as.character(matchingSYN_deDup$mgi_symbol)
    new_exp  = rbind(exp_Good,exp_Bad)

    print(sprintf("%s rows should have been corrected by checking synonms",dim(matchingSYN)[1]))
    still_not_MGI = sort(rownames(new_exp)[!rownames(new_exp) %in% all_mgi])
    print(sprintf("%s rows STILL do not have proper MGI symbols",length(still_not_MGI)))
    if(printAllBadSymbols==TRUE){
        print(still_not_MGI)
    }
    return(new_exp)
}
