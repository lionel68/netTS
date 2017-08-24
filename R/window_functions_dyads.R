#' dyadTS function
#'
#' This function will take a dataframe with events between individuals/objects, and take dyad level measures using a moving window approach.
#' A time column is required.
#' @param event.data dataframe containing events between individuals/objects
#' @param windowSize size of the window in which to make network measures (should be the same scale as the time column)
#' @param windowShift the amount to shift the moving window for each measure
#' @param windowStart The time of the first window. This should corespond to the first events.
#' @param type is the type of measure to take in each window. Currently available are: sum strength, mean strength, proportion weight, relative strength
#' @param directedNet Whether the events are directed or no: true or false.
#' @param threshold minimum number of events to calculate a network measure (otherwise NA is produced).
#' @param startDate Optional argument to set the date of the first event.
#' @export
#' @import igraph
#' @importFrom plyr rbind.fill
#' @importFrom lubridate dmy
#' @importFrom lubridate days
#' @examples
#'
#' ts.out<-dyadTS(event.data=groomEvents[1:200,])
#' dyadTS.plot(ts.out)
#'
dyadTS <- function (event.data,windowSize =30,windowShift= 1, type="proportion",directedNet=T, threshold=30,windowStart=0, startDate=NULL){

  #intialize
  windowEnd=windowStart+windowSize
  netValues <- data.frame()

  if(windowEnd>max(event.data$time))print("Error: the window size is set larger than the max time difference")

  #set global dataframe with proper names
  g.global <- create.a.network(event.data)
  names.edges<-paste(get.edgelist(g.global)[,1],get.edgelist(g.global)[,2],sep="_")
  netValues<- t(rep(1,length(names.edges)))
  colnames(netValues)<-names.edges


  #for every window
  while (windowStart + windowSize<=max(event.data$time)) {

    #subset the data
    df.window<-create.window(event.data, windowStart, windowEnd)

    #if there is enough data in this window...
    if(nrow(df.window)>threshold){

      #create a network
      g <- create.a.network(df.window)

      #calculate measure
      if(type=='weight')df.measure <- dyad_weight(g)
      if(type=='sum')df.measure <- dyad_sum(g)
      if(type=='mean')df.measure <- dyad_mean(g)
      if(type=='proportion')df.measure <- dyad_proportion(g)
      if(type=='diff')df.measure <- dyad_diff(g)

      #create a dataframe with the measures
      df.measure$windowStart <- windowStart
      df.measure$windowEnd <- windowEnd

    } else {
      df.measure <- as.data.frame(NA)
    }

    #get window date range
    windowStartDate <- NA
    windowEndDate <- NA
    if(is.null(startDate)==FALSE){
      windowStartDate <- mdy(startDate) + days(windowStart)
      windowEndDate <- mdy(startDate) + days(windowEnd)
    }
    df.measure$windowStartDate <- windowStartDate
    df.measure$windowEndDate <- windowEndDate
    df.measure$nEvents <- nrow(df.window)

    #record values
    netValues <- rbind.fill(list(as.data.frame(netValues),as.data.frame(df.measure) ))

    #move window over
    windowEnd = windowEnd + windowShift
    windowStart = windowStart + windowShift

  }

  return (netValues[-1,])
}


#' dyad_sum function
#'
#' This function will take a graph and take dyad level sum of weights.
#' @param g graph to extract dyad measures from
#' @export
#' @import igraph
#' @importFrom plyr rbind.fill
#'
dyad_weight <- function(g){

  weight.vector <- vector()

  for(i in 1:length(E(g))){

    weight.value=E(g)[i]$weight

    weight.vector[length(weight.vector)+1] <- weight.value
  }

  df.weight <- data.frame(t(weight.vector))
  colnames(df.weight)<-paste(get.edgelist(g)[,1],get.edgelist(g)[,2],sep="_")

  return (df.weight)

}


#' dyad_sum function
#'
#' This function will take a graph and take dyad level sum of weights.
#' @param g graph to extract dyad measures from
#' @export
#' @import igraph
#' @importFrom plyr rbind.fill
#'
dyad_sum <- function(g){

  sum.vector <- vector()

  for(i in 1:length(E(g))){

    sum.value=E(g)[i]$weight

    #check to see if there is a reciprical edge
    if(is.directed(g) & which_mutual(g,E(g)[i])){
      sum.value = sum( E(g)[ends(g,E(g)[i])[,2] %--% ends(g,E(g)[i])[,1]]$weight)
    }

    sum.vector[length(sum.vector)+1] <- sum.value
  }

  df.sum <- data.frame(t(sum.vector))
  colnames(df.sum)<-paste(get.edgelist(g)[,1],get.edgelist(g)[,2],sep="_")

  return (df.sum)

}

#' dyad_mean function
#'
#' This function will take a graph and take dyad level mean weight.
#' @param g graph to extract dyad measures from
#' @export
#' @import igraph
#' @importFrom plyr rbind.fill
#'
dyad_mean <- function(g){

  mean.vector <- vector()

  for(i in 1:length(E(g))){

    mean.value=E(g)[i]$weight

    #check to see if there is a reciprical edge
    if(is.directed(g) & which_mutual(g,E(g)[i])){
      mean.value = mean( E(g)[ends(g,E(g)[i])[,2] %--% ends(g,E(g)[i])[,1]]$weight)
    }

    mean.vector[length(mean.vector)+1] <- mean.value
  }

  df.mean <- data.frame(t(mean.vector))
  colnames(df.mean)<-paste(get.edgelist(g)[,1],get.edgelist(g)[,2],sep="_")

  return (df.mean)

}

#' dyad_diff function
#'
#' This function will take a graph and take dyad level difference in weights.
#' @param g graph to extract dyad measures from
#' @export
#' @import igraph
#' @importFrom plyr rbind.fill
#'
dyad_diff <- function(g){

  diff.vector <- vector()

  for(i in 1:length(E(g))){

    diff.value=0

    #check to see if there is a reciprical edge
    if(is.directed(g) & which_mutual(g,E(g)[i])){
      diff.values = ( E(g)[ends(g,E(g)[i])[,2] %--% ends(g,E(g)[i])[,1]]$weight)
      diff.value = abs(diff.values[1]-diff.values[2])
    }

    diff.vector[length(diff.vector)+1] <- diff.value
  }

  df.diff <- data.frame(t(diff.vector))
  colnames(df.diff)<-paste(get.edgelist(g)[,1],get.edgelist(g)[,2],sep="_")

  return (df.diff)

}


#' dyad_proportion function
#'
#' This function will take a graph and take dyad proportion of weights.
#' @param g graph to extract dyad measures from
#' @export
#' @import igraph
#' @importFrom plyr rbind.fill
#'
dyad_proportion <- function(g){

  prop.vector <- vector()

  for(i in 1:length(E(g))){

    if(is.directed(g)==F){

      edge.value=E(g)[i]$weight

      start.node.1<-ends(g, E(g)[i])[1]
      total.weight.1 <- sum(E(g)[from(start.node.1)]$weight)

      start.node.2<-ends(g, E(g)[i])[2]
      total.weight.2 <- sum(E(g)[from(start.node.2)]$weight)


      prop.value <- ( (edge.value / total.weight.1) + (edge.value / total.weight.2) ) / 2

    } else {

      #check to see if there is a reciprical edge

      edge.value=E(g)[i]$weight

      start.node<-ends(g, E(g)[i])[1]
      total.weight <- sum(E(g)[from(start.node)]$weight)

      prop.value <- edge.value / total.weight

    }

    prop.vector[length(prop.vector)+1] <- prop.value

  }


  df.prop <- data.frame(t(prop.vector))
  colnames(df.prop)<-paste(get.edgelist(g)[,1],get.edgelist(g)[,2],sep="_")

  return (df.prop)

}

#' Plotting function for dyadTS dataframes
#'
#' This function will plot the output of the dyadTS function
#' @param df.ts output dataframe from the dyadTS function
#' @param nEvents Opional argument to plot the number of events
#' @param dates Optional argument to plot the date as opposed to the time since the first event
#' @import ggplot2
#' @importFrom reshape2 melt
#' @examples
#'
#' ts.out<-dyadTS(event.data=groomEvents[1:200,])
#' dyadTS.plot(ts.out)
#'
#' @export
dyadTS.plot <- function(df.ts, nEvents = FALSE, dates = FALSE){

  if(nEvents ==FALSE){

    if(dates==FALSE){

      df.melt<-melt(df.ts, id=c("windowEnd"))
      df.melt<-df.melt[complete.cases(df.melt),]
      df.melt<-filter(df.melt, variable != "windowStart" & variable != "windowEnd" & variable != "windowStartDate" & variable != "windowEndDate", variable != "nEvents")

      fig<-ggplot(df.melt, aes(x=windowEnd, y=value, group=variable, color=variable))+ geom_line()+
        labs(x= "Time since start")

    } else {

      df.melt<-melt(df.ts, id=c("windowEndDate"))
      df.melt<-df.melt[complete.cases(df.melt),]
      df.melt<-filter(df.melt, variable != "windowStart" | variable != "windowEnd" | variable != "windowStartDate" | variable != "windowEndDate", variable != "nEvents")

      fig<-ggplot(df.melt, aes(x=windowEndDate, y=value, group=variable, color=variable))+ geom_line()+
        labs(x= "Time since start")
    }

  } else{

    if(dates==FALSE){

      df.melt<-melt(df.ts, id=c("windowEnd"))
      df.melt<-df.melt[complete.cases(df.melt),]
      df.melt<-filter(df.melt, variable != "windowStart" | variable != "windowEnd" | variable != "windowStartDate" | variable != "windowEndDate")

      fig<-ggplot(df.melt, aes(x=windowEnd, y=nEvents, group=variable, color=variable))+ geom_line()+
        labs(x= "Time since start")

    } else {

      df.melt<-melt(df.ts[,(ncol(df.ts)-1)], id=c("windowEndDate"))
      df.melt<-df.melt[complete.cases(df.melt),]
      df.melt<-filter(df.melt, variable != "windowStart" | variable != "windowEnd" | variable != "windowStartDate" | variable != "windowEndDate")

      fig<-ggplot(df.melt, aes(x=windowEndDate, y=nEvents, group=variable, color=variable))+ geom_line()+
        labs(x= "Time since start")
    }
  }

  fig

  return(fig)
}