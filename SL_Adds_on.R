#==================== Super Learner Cross-validation=============================
SL_crossval=function(dta,target,folds=10){
  index_crossval=caret::createFolds(dta%>%pull(target),k=folds,returnTrain = F)
  Xtrain=purrr::map(seq_along(index_crossval),
                    function(i){
                      dta%>%slice(-index_crossval[[i]])%>%
                        dplyr::select(-target)
                    })
  Ytrain=purrr::map(seq_along(index_crossval),
                    function(i){
                      dta%>%slice(-index_crossval[[i]])%>%pull(target)
                    })
  
  Xtest=purrr::map(seq_along(index_crossval),
                   function(i){
                     dta%>%slice(index_crossval[[i]])%>%dplyr::select(-target)
                   })
  Ytest=purrr::map(seq_along(index_crossval),
                   function(i){
                     dta%>%slice(index_crossval[[i]])%>%pull(target)
                   })
  data_list=list("Xtrain"=Xtrain,"Ytrain"=Ytrain,"Xtest"=Xtest,"Ytest"=Ytest)
  return(data_list)
}

#=======================Super Learner Prediction===========================
predict_SuperLearner=function (object, newdata, X = NULL, Y = NULL, onlySL = FALSE, 
                               ...) 
{
  if (missing(newdata)) {
    out <- list(pred = object$SL.predict, library.predict = object$library.predict)
    return(out)
  }
  if (!object$control$saveFitLibrary) {
    stop("This SuperLearner fit was created using control$saveFitLibrary = FALSE, so new predictions cannot be made.")
  }
  k <- length(object$libraryNames)
  predY <- matrix(NA, nrow = nrow(newdata), ncol = k)
  colnames(predY) <- object$libraryNames
  if (onlySL) {
    whichLibrary <- which(object$coef > 0)
    predY <- matrix(0, nrow = nrow(newdata), ncol = k)
    for (mm in whichLibrary) {
      newdataMM <- subset(newdata, select = object$whichScreen[object$SL.library$library[mm, 
                                                                                         2], ])
      family <- object$family
      XMM <- if (is.null(X)) {
        NULL
      }
      else {
        subset(X, select = object$whichScreen[object$SL.library$library[mm, 
                                                                        2], ])
      }
      predY1[, mm] <- do.call("predict", list(object = object$fitLibrary[[mm]], 
                                              newdata = newdataMM, family = family, X = XMM, 
                                              Y = Y, ...))
      predY1[, mm]=predY$data[,1]
    }
    getPred <- object$method$computePred(predY = predY, 
                                         coef = object$coef, control = object$control)
    out <- list(pred = getPred, library.predict = predY)
  }
  else {
    for (mm in seq(k)) {
      newdataMM <- subset(newdata, select = object$whichScreen[object$SL.library$library[mm, 
                                                                                         2], ])
      family <- object$family
      XMM <- if (is.null(X)) {
        NULL
      }
      else {
        subset(X, select = object$whichScreen[object$SL.library$library[mm, 
                                                                        2], ])
      }
      predY1 <- do.call("predict", list(object = object$fitLibrary[[mm]], 
                                        newdata = newdataMM, family = family, X = XMM, 
                                        Y = Y, ...))
      predY[, mm]=predY1$data[,1]
    }
    getPred <- object$method$computePred(predY = predY, 
                                         coef = object$coef, control = object$control)
    out <- list(pred = getPred, library.predict = predY)
  }
  return(out)
}


#====================Training Super Learner===================================
SL_train=function(SLmodel,dta,verbose=T,...){
  
  
  mod=purrr::map(seq_along(dta$Ytrain),
                 function(i){
                   
                   if(verbose){
                     cat("Folds",i,"\n")
                     tictoc::tic("Elapsed Time:")
                     res=SLmodel(dta$Ytrain[[i]],dta$Xtrain[[i]],...)
                     tictoc::toc()
                     return(res)
                   }else{
                     SLmodel(dta$Ytrain[[i]],dta$Xtrain[[i]],...)
                   }
                   
                 })
  # browser()
  coefSL=purrr::map(seq_along(mod),function(i) coef(mod[[i]]))
  pred=purrr::map(seq_along(mod),function(i){
    predict_SuperLearner(mod[[i]],dta$Xtest[[i]])
  } )
  return(list("prediction"=pred,"coef_SL"=coefSL,"truth"=dta$Ytest))
}


# =================Calculate Performance of Super Learner================

binary_enc=function(y,thres=0.5,code=c(0,1)){
  
  ifelse(y>thres,code[2],code[1])
}

SLperformance=function(train,measure,type="SL"){
  if(type=="SL"){
    #    browser()
    prediction=purrr::invoke(c,purrr::map(seq_along(train$prediction),function(i){
      train$prediction[[i]]$pred
    }))
    prediction=binary_enc(prediction,code = c(1,0))
    truth=purrr::invoke(c,purrr::map(seq_along(train$truth),function(i){
      train$truth[[i]]
    }))
    measure(truth,prediction)
  }else{
    #Super Learner Prediction
    prediction=purrr::invoke(c,purrr::map(seq_along(train$prediction),function(i){
      train$prediction[[i]]$pred
    }))
    prediction=binary_enc(prediction,code = c(1,0))
    truth=purrr::invoke(c,purrr::map(seq_along(train$truth),function(i){
      train$truth[[i]]
    }))
    SL_prediction=measure(truth,prediction)
    #Prediction each folds
    truth=train$truth
    prediction=purrr::map(seq_along(train$prediction),function(i){
      train$prediction[[i]]$pred
    })
    prediction=purrr::map(prediction,binary_enc,code = c(1,0))
    folds_prediction=purrr::map2_dbl(truth,prediction,measure)
    return(list("final_prediction"=SL_prediction,
                "folds_prediction"=folds_prediction))
  }
}