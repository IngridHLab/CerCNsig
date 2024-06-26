fitComponent<-function(dat,dist="norm",seed=77777,model_selection="BIC",min_prior=0.001,niter=1000,nrep=1,min_comp=2,max_comp=10)
{
    control<-new("FLXcontrol")
    control@minprior<-min_prior
    control@iter.max<-niter
    
    set.seed(seed)
    if(dist=="norm")
    {
        if(min_comp==max_comp)
        {
            fit<-flexmix::flexmix(dat ~ 1,model=flexmix::FLXMCnorm1(),k=min_comp,control=control)
        }else{
            fit<-flexmix::stepFlexmix(dat ~ 1,model = flexmix::FLXMCnorm1(),k=min_comp:max_comp,nrep=nrep,control=control)
            fit<-flexmix::getModel(fit,which=model_selection)
        }
        
    }else if(dist=="pois")
    {
        if(min_comp==max_comp)
        {
            fit<-flexmix::flexmix(dat ~ 1,model=flexmix::FLXMCmvpois(),k=min_comp,control=control)
        }else{
            fit<-flexmix::stepFlexmix(dat ~ 1,model = flexmix::FLXMCmvpois(),k=min_comp:max_comp,nrep=nrep,control=control)
            fit<-flexmix::getModel(fit,which=model_selection)
        }
    }
    fit
}

calculateSumOfPosteriors<-function(CN_feature,components,name, rowIter = 1000, cores = 1)
{
    
    if(cores > 1){
        require(foreach)
        require(doMC)

        len = dim(CN_feature)[1]
        iters = floor( len / rowIter )
        lastiter = iters[length(iters)]

        registerDoMC(cores)
        curr_posterior = foreach( i=0:iters, .combine=rbind) %dopar% {
            start = i*rowIter+1
            if(i != lastiter) { end = (i+1)*rowIter } else { end = len }
                flexmix::posterior(components,data.frame(dat=as.numeric(CN_feature[start:end,2])))
        }
    } else {
        curr_posterior<-flexmix::posterior(components,data.frame(dat=as.numeric(CN_feature[,2])))
    }

    mat<-cbind(CN_feature,curr_posterior)
    posterior_sum<-c()
    
    ## foreach and parallelising doesn't make the following code faster.
    for(i in unique(mat$ID))
    {
        posterior_sum<-rbind(posterior_sum,colSums(mat[mat$ID==i,c(-1,-2)]))
    }
    params<-flexmix::parameters(components)
    if(!is.null(nrow(params)))
    {
        posterior_sum<-posterior_sum[,order(params[1,])]
    }
    else
    {
        posterior_sum<-posterior_sum[,order(params)]
    }
    colnames(posterior_sum)<-paste0(name,1:ncol(posterior_sum))
    rownames(posterior_sum)<-rownames(unique(mat$ID))
    posterior_sum
}

getSegsize<-function(abs_profiles)
{
    out<-c()
    samps<-getSampNames(abs_profiles)
    for(i in samps)
    {
        if(class(abs_profiles)=="QDNAseqCopyNumbers")
        {
            segTab<-getSegTable(abs_profiles[,which(colnames(abs_profiles)==i)])
        }
        else
        {
            segTab<-abs_profiles[[i]]
            colnames(segTab)[4]<-"segVal"
        }
        segTab$segVal[as.numeric(segTab$segVal)<0]<-0
        seglen<-(as.numeric(segTab$end)-as.numeric(segTab$start))
        seglen<-seglen[seglen>0]
        out<-rbind(out,cbind(ID=rep(i,length(seglen)),value=seglen))
    }
    rownames(out)<-NULL
    data.frame(out,stringsAsFactors = F)
}

getBPnum<-function(abs_profiles,chrlen)
{
    out<-c()
    samps<-getSampNames(abs_profiles)
    for(i in samps)
    {
        if(class(abs_profiles)=="QDNAseqCopyNumbers")
        {
            segTab<-getSegTable(abs_profiles[,which(colnames(abs_profiles)==i)])
        }else
        {
            segTab<-abs_profiles[[i]]
            colnames(segTab)[4]<-"segVal"
        }
        chrs<-unique(segTab$chromosome)
        allBPnum<-c()
        for(c in chrs)
        {
            currseg<-segTab[segTab$chromosome==c,]
            intervals<-seq(1,chrlen[chrlen[,1]==paste0("chr",c),2]+10000000,10000000)
            res <- hist(as.numeric(currseg$end[-nrow(currseg)]),breaks=intervals,plot=FALSE)$counts
            allBPnum<-c(allBPnum,res)
        }
        out<-rbind(out,cbind(ID=rep(i,length(allBPnum)),value=allBPnum))
    }
    rownames(out)<-NULL
    data.frame(out,stringsAsFactors = F)
}

getOscilation<-function(abs_profiles,chrlen)
{
    out<-c()
    samps<-getSampNames(abs_profiles)
    for(i in samps)
    {
        if(class(abs_profiles)=="QDNAseqCopyNumbers")
        {
            segTab<-getSegTable(abs_profiles[,which(colnames(abs_profiles)==i)])
        }else
        {
            segTab<-abs_profiles[[i]]
            colnames(segTab)[4]<-"segVal"
        }
        chrs<-unique(segTab$chromosome)
        oscCounts<-c()
        for(c in chrs)
        {
            currseg<-segTab[segTab$chromosome==c,"segVal"]
            currseg<-round(as.numeric(currseg))
            if(length(currseg)>3)
            {
                prevval<-currseg[1]
                count=0
                for(j in 3:length(currseg))
                {
                    if(currseg[j]==prevval&currseg[j]!=currseg[j-1])
                    {
                        count<-count+1
                    }else{
                        oscCounts<-c(oscCounts,count)
                        count=0
                    }
                    prevval<-currseg[j-1]
                }
            }
        }
        out<-rbind(out,cbind(ID=rep(i,length(oscCounts)),value=oscCounts))
        if(length(oscCounts)==0)
        {
            out<-rbind(out,cbind(ID=i,value=0))
        }
    }
    rownames(out)<-NULL
    data.frame(out,stringsAsFactors = F)
}

getCentromereDistCounts<-function(abs_profiles,centromeres,chrlen)
{
    out<-c()
    samps<-getSampNames(abs_profiles)
    for(i in samps)
    {
        if(class(abs_profiles)=="QDNAseqCopyNumbers")
        {
            segTab<-getSegTable(abs_profiles[,which(colnames(abs_profiles)==i)])
        }else
        {
            segTab<-abs_profiles[[i]]
            colnames(segTab)[4]<-"segVal"
        }
        chrs<-unique(segTab$chromosome)
        all_dists<-c()
        for(c in chrs)
        {
            if(nrow(segTab)>1)
            {
                starts<-as.numeric(segTab[segTab$chromosome==c,2])[-1]
                segstart<-as.numeric(segTab[segTab$chromosome==c,2])[1]
                ends<-as.numeric(segTab[segTab$chromosome==c,3])
                segend<-ends[length(ends)]
                ends<-ends[-length(ends)]
                centstart<-as.numeric(centromeres[substr(centromeres[,2],4,5)==c,3])
                centend<-as.numeric(centromeres[substr(centromeres[,2],4,5)==c,4])
                chrend<-chrlen[substr(chrlen[,1],4,5)==c,2]
                ndist<-cbind(rep(NA,length(starts)),rep(NA,length(starts)))
                ndist[starts<=centstart,1]<-(centstart-starts[starts<=centstart])/(centstart-segstart)*-1
                ndist[starts>=centend,1]<-(starts[starts>=centend]-centend)/(segend-centend)
                ndist[ends<=centstart,2]<-(centstart-ends[ends<=centstart])/(centstart-segstart)*-1
                ndist[ends>=centend,2]<-(ends[ends>=centend]-centend)/(segend-centend)
                ndist<-apply(ndist,1,min)
                
                all_dists<-rbind(all_dists,sum(ndist>0))
                all_dists<-rbind(all_dists,sum(ndist<=0))
            }
        }
        if(nrow(all_dists)>0)
        {
            out<-rbind(out,cbind(ID=i,ct1=all_dists[,1]))
        }
    }
    rownames(out)<-NULL
    data.frame(out,stringsAsFactors = F)
}


getChangepointCN<-function(abs_profiles)
{
    out<-c()
    samps<-getSampNames(abs_profiles)
    for(i in samps)
    {
        if(class(abs_profiles)=="QDNAseqCopyNumbers")
        {
            segTab<-getSegTable(abs_profiles[,which(colnames(abs_profiles)==i)])
        }
        else
        {
            segTab<-abs_profiles[[i]]
            colnames(segTab)[4]<-"segVal"
        }
        segTab$segVal[as.numeric(segTab$segVal)<0]<-0
        chrs<-unique(segTab$chromosome)
        allcp<-c()
        for(c in chrs)
        {
            currseg<-as.numeric(segTab[segTab$chromosome==c,"segVal"])
            allcp<-c(allcp,abs(currseg[-1]-currseg[-length(currseg)]))
        }
        if(length(allcp)==0)
        {
            allcp<-0 #if there are no changepoints
        }
        out<-rbind(out,cbind(ID=rep(i,length(allcp)),value=allcp))
    }
    rownames(out)<-NULL
    data.frame(out,stringsAsFactors = F)
}

getCN<-function(abs_profiles)
{
    out<-c()
    samps<-getSampNames(abs_profiles)
    for(i in samps)
    {
        if(class(abs_profiles)=="QDNAseqCopyNumbers")
        {
            segTab<-getSegTable(abs_profiles[,which(colnames(abs_profiles)==i)])
        }
        else
        {
            segTab<-abs_profiles[[i]]
            colnames(segTab)[4]<-"segVal"
        }
        segTab$segVal[as.numeric(segTab$segVal)<0]<-0
        cn<-as.numeric(segTab$segVal)
        out<-rbind(out,cbind(ID=rep(i,length(cn)),value=cn))
    }
    rownames(out)<-NULL
    data.frame(out,stringsAsFactors = F)
}

getSampNames<-function(abs_profiles)
{
    if(class(abs_profiles)=="QDNAseqCopyNumbers")
    {
        samps<-colnames(abs_profiles)
    }
    else
    {
        samps<-names(abs_profiles)
    }
    samps
}

getSegTable<-function(x)
{
    dat<-x
    sn<-Biobase::assayDataElement(dat,"segmented")
    fd <- Biobase::fData(dat)
    fd$use -> use
    fdfiltfull<-fd[use,]
    sn<-sn[use,]
    segTable<-c()
    for(c in unique(fdfiltfull$chromosome))
    {
        snfilt<-sn[fdfiltfull$chromosome==c]
        fdfilt<-fdfiltfull[fdfiltfull$chromosome==c,]
        sn.rle<-rle(snfilt)
        starts <- cumsum(c(1, sn.rle$lengths[-length(sn.rle$lengths)]))
        ends <- cumsum(sn.rle$lengths)
        lapply(1:length(sn.rle$lengths), function(s) {
            from <- fdfilt$start[starts[s]]
            to <- fdfilt$end[ends[s]]
            segValue <- sn.rle$value[s]
            c(fdfilt$chromosome[starts[s]], from, to, segValue)
        }) -> segtmp
        segTableRaw <- data.frame(matrix(unlist(segtmp), ncol=4, byrow=T),stringsAsFactors=F)
        segTable<-rbind(segTable,segTableRaw)
    }
    colnames(segTable) <- c("chromosome", "start", "end", "segVal")
    segTable
}


getPloidy<-function(abs_profiles)
{
  out<-c()
  samps<-getSampNames(abs_profiles)
  for(i in samps)
  {
    if(class(abs_profiles)=="QDNAseqCopyNumbers")
    {
      segTab<-getSegTable(abs_profiles[,which(colnames(abs_profiles)==i)])
    }
    else
    {
      segTab<-abs_profiles[[i]]
      colnames(segTab)[4]<-"segVal"
    }
    segLen<-(as.numeric(segTab$end)-as.numeric(segTab$start))
    ploidy<-sum((segLen/sum(segLen))*as.numeric(segTab$segVal))
    out<-c(out,ploidy)
  }
  data.frame(out,stringsAsFactors = F)
}


normaliseMatrix<-function(signature_by_sample,sig_thresh=0.01)
{
    norm_const<-colSums(signature_by_sample)
    sample_by_signature<-apply(signature_by_sample,1,function(x){x/norm_const})
    sample_by_signature<-apply(sample_by_signature,1,lower_norm,sig_thresh)
    signature_by_sample<-t(sample_by_signature)
    norm_const<-apply(signature_by_sample,1,sum)
    sample_by_signature<-apply(signature_by_sample,2,function(x){x/norm_const})
    signature_by_sample<-t(sample_by_signature)
    signature_by_sample
}

lower_norm<-function(x,sig_thresh=0.01)
{
    new_x<-x
    for(i in 1:length(x))
    {
        if(x[i]<sig_thresh)
        {
            new_x[i]<-0
        }
    }
    new_x
}



