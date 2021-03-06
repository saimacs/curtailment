# This script makes predictions for each DR day
# based on eigen PCA model
# Traindata is 2/3 of the entire data.

rm(list=ls())
beginDR = 54 # 1:15 PM
endDR = 69 # 5:00 PM
vectorLength = 199
absent2012 = FALSE

#read DR vectors
setwd("/Users/saima/Desktop/curtailment/")

# Find buildings from the DR schedule
schedule12 = read.csv("data/DRevents2012.csv",header=TRUE)
schedule13 = read.csv("data/DRevents2013.csv",header=TRUE)
schedule14 = read.csv("data/DRevents2014.csv",header=TRUE)

buildings12 = as.character(unique(schedule12$Building))
buildings13 = as.character(unique(schedule13$Building))
buildings14 = as.character(unique(schedule14$Building))

testBuildings = unique(c(buildings13,buildings14))
allBuildings = unique(c(buildings12,buildings13,buildings14))
numBuildings = length(allBuildings)

#-------------------------------
#do for TOP ranging from 2:50
for(TOP in 2:50){
  cat("\n TOP = ",TOP,"\n")
  
  # do for all buildings
  allMape = list()
  allDayCounts = list()
  setwd("/Users/saima/Desktop/curtailment/makedatasets/DRdataset/")
  
  for (j in 1:numBuildings){
    bd = allBuildings[j]
    cat(j,",")
    
    # find DR vector file names
    fList = list.files(pattern = paste("^",bd,sep=""))
    if(length(fList)==0){
      next
    }
    numDays = length(fList)
    
    # read DR vectors
    DRvectors = NULL
    skipped = NULL
    for (n in 1:numDays){
      vector = read.csv(fList[n],header=TRUE,as.is=TRUE)  
      vector = vector[,1]
      if(length(vector) != vectorLength){
        skipped = c(skipped,n)
        next  # skip this record
      }
      DRvectors = rbind(DRvectors,vector)
    }
    # update numdays
    fList = fList[-skipped]
    numDays = length(fList)
    numTrainDays = round((2/3)*numDays)
    numTestDays = numDays - numTrainDays
    
    trainIndices = c(1:numTrainDays)
    testIndices = c((numTrainDays+1):numDays)
    
    ######################## 
    mape = numeric(numTestDays)
    obsDayCount = numeric(numTestDays)
    
    # make predictions
    for (i in 1:numTestDays){
      testIndex = testIndices[i]
      testVector = DRvectors[testIndex,(beginDR:endDR)]
      
      #--------------------------
      # define training data
      wkend = c(198,199)
      trainData = DRvectors[trainIndices,-wkend]
      mu = apply(trainData,2,mean)
      sigma = apply(trainData,2,sd)
      
      # normalize kwh and temp columns
      normTrainData = scale(trainData,center = TRUE,scale = TRUE)
      
      # find eigen vectors
      covTrainData = cov(normTrainData)
      if(sum(is.na(covTrainData))>0){
        next  
      }
      eigenValuesTrainData = eigen(covTrainData)$values
      eigenVectorsTrainData = eigen(covTrainData)$vectors
      
      # save eigen vectors
      evFile = paste("../../NormEigenVectors/",bd,"-ev.csv",sep="")
      write.csv(eigenVectorsTrainData,evFile,row.names=F)
      
      # No. of observed features in preDR signature are
      # kwh & temp before DR, and 5 weekdays
      preDRindices = c(1:(beginDR-1),(96+1):(96+beginDR-1),(192+1):197)
      preDRsignature = DRvectors[testIndex,preDRindices]
      preDRev = eigenVectorsTrainData[preDRindices,(1:TOP)]
      preDRmu = mu[preDRindices]
      preDRsigma = sigma[preDRindices]
      
      # calculate weights
      normSignature = (preDRsignature-preDRmu)%*%diag(preDRsigma^(-1))
      weights = normSignature %*% preDRev
      
      # make predictions
      inDRindices = c(beginDR:endDR)
      inDRev = eigenVectorsTrainData[inDRindices,(1:TOP)]
      inDRmu = mu[inDRindices]
      inDRsigma = sigma[inDRindices]
      
      sumev = 0
      for (k in 1:length(weights)){
        sumev = sumev + weights[k]*inDRev[,k]
      }
      predVector = ((sumev + inDRmu) %*% diag(inDRsigma))
      
      #--------------------------
      # calculate errors
      ape = abs(predVector - testVector)/testVector
      mape[i] = mean(ape)
      allMape[[j]] = mape
      
      obsDayCount[i] = length(trainIndices)
      allDayCounts[[j]] = obsDayCount
    } 
  }
  
  # save results
  setwd("/Users/saima/Desktop/curtailment/MAPE/mape-evs/")
  for(i in 1:length(allMape)){
    if(is.null(allMape[[i]])){
      next  
    }
    df = data.frame(mape = allMape[[i]],
                    daycounts = allDayCounts[[i]])
    opFile = paste(TOP,"ev-mape-",allBuildings[i],".csv",sep="")
    write.csv(df,opFile,row.names=F)    
  }
    
}
