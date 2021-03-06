

#' graphTS function
#'
#' This function will take a dataframe with events between individuals/objects, and take network measures using a moving window approach.
#' @param data A dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param windowsize The size of the moving window in which to take network measures. These should be provided as e.g., days(30), hours(5), ... etc.
#' @param windowshift The amount to shift the moving window for each measure. Again times should be provided as e.g., days(1), hours(1), ... etc.
#' @param measureFun This is a function that takes as an input a igraph network and returns a single value. There are functions within netTS (see details), and custom made functions can be used.
#' @param directed Whether the events are directed or no: true or false.
#' @param lagged Whether the network measure function used requires the comparison between two networks. e.g., comparing the current network to one lagged by 10 days. If TRUE the measureFun should take two graphs as input and return a single value. The order of inputs in the function is the lagged network followed by the current network.
#' @param lag If lagged is set to TRUE, this is the lag at which to compare networks.
#' @param firstNet If lagged is set to TRUE, this forces the comparisons between graphs to always be between the current and first graph.
#' @param cores This allows for multiple cores to be used while generating networks and calculating network measures.
#' @param nperm This allows for the estimation the network measure assuming random permutations. Currently the 95 percent quantiles are returned.
#' @param probs When nperm > 0 this will determine the probability of the permutation values returned from the permuations.
#' @param check.convergence If this is TRUE the function will calculate network measures for each window using random subsets of the data to measure the stability of the network measure. The value returned is the slope from the random subsets of decreasing size.
#' @param random.sample.size If check.convergence is TRUE this specifices the minimum size of the random subset used in calculating the convergence slope, i.e., minimum random subset size = actual sample size within a window - random.sample.size.
#' @param trim Whether nodes that are in windows beyond their first/last observation time are removed (i.e., only partially within a time window).
#' @param SRI Whether to convert edges to the simple ratio index: Nab / (Nab + Na + Nb). Default is set to FALSE.
#' @export
#' @importFrom lubridate days
#' @examples
#'
#' ts.out<-graphTS(data=groomEvents[1:200,])
#'
graphTS <- function (data,windowsize = days(30), windowshift= days(1), measureFun=degree_mean,directed=FALSE, lagged=FALSE, lag=1, firstNet=FALSE, cores=1, nperm=0, probs=0.95, check.convergence=FALSE,random.sample.size=30, trim=FALSE, SRI=FALSE){

  #extract networks from the dataframe
  if(cores > 1){
    graphlist <- extract_networks_para(data, windowsize, windowshift, directed, cores = 2, trim=trim, SRI=SRI)
  } else {
    graphlist <- extract_networks(data, windowsize, windowshift, directed, trim=trim, SRI=SRI)
  }

  #extract measures from the network list
  if(lagged==FALSE){
    values <- extract_measure_network(graphlist, measureFun)
  } else {
    values <- extract_lagged_measure_network(graphlist, measureFun, lag, firstNet)
  }

  if(nperm>0){
    perm.values <- permutation.graph.values(data, windowsize, windowshift, directed, measureFun = measureFun, probs=probs, SRI=SRI)
    values <- cbind(data.frame(values),perm.values)
    values<-values[,c(1,5,6,2,3,4)]
  }

  if(check.convergence==TRUE){
    convergence.values <- convergence.check(data, windowsize, windowshift, directed, measureFun = measureFun,random.sample.size, SRI=SRI)
    values <- cbind(data.frame(values),convergence.values)
  }

  return (values)

}


#' Convergence check
#'
#' This function will estimate the convergence of the chosen network measure using random subsets of the data.
#' @param data Dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param windowsize The size of each window in which to generate a network.
#' @param windowshift The amount of time to shift the window when generating networks.
#' @param directed Whether to consider the network as directed or not (TRUE/FALSE).
#' @importFrom stats coef
#' @importFrom stats lm
#' @importFrom igraph set_graph_attr
#' @export
#'
#'
convergence.check<-function(data, windowsize, windowshift, directed = FALSE, measureFun,random.sample.size, SRI=FALSE){

  #intialize times
  windowstart <- min(data[,4])
  windowend=windowstart+windowsize
  if(windowend>max(data[,4]))print("warnning: the window size is set larger than the observed data.")

  #for every window generate a network
  conv.values <- vector()
  while (windowstart + windowsize<=max(data[,4])) {

    #subset the data
    df.window<-create.window(data, windowstart, windowend)
    Observation.Events <- nrow(df.window)

    #store network measures
    net.measures <- data.frame(value=-1,sample=-1)

    if(Observation.Events>1){

      #Number of
      for(j in seq(max(Observation.Events-random.sample.size,1),Observation.Events,by=1)){

        #subset window
        df.sub<-df.window[sample(nrow(df.window),j),]

        #create a network and add it to the list
        g <- create.a.network(df.sub, directed = directed, SRI)
        g <- set_graph_attr(g, "nEvents", Observation.Events)
        g <- set_graph_attr(g, "windowstart", windowstart)
        g <- set_graph_attr(g, "windowend", windowend)

        #take measure
        net.measures <- rbind(net.measures,data.frame(value=measureFun(g),sample=j))
      }

    } else {
      net.measures <- rbind(net.measures,data.frame(value=NA,sample=0))
    }

    net.measures<-net.measures[-1,]
    net.measures<-net.measures[complete.cases(net.measures),]
    #calculate convergence (right now just using the slope...)

    if(nrow(net.measures)>0){
      conv.values[length(conv.values)+1] <- coef(lm(value~sample, data = net.measures))["sample"]
    } else {
      conv.values[length(conv.values)+1] <- NA
    }

    #move the window
    windowend = windowend + windowshift
    windowstart = windowstart + windowshift


  }

  return(conv.values)

}


#' Extract networks from a moving window
#'
#' This function will create a time series of networks from a dataframe with relational events and a time stamp.
#' @param data Dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param windowsize The size of each window in which to generate a network.
#' @param windowshift The amount of time to shift the window when generating networks.
#' @param directed Whether to consider the network as directed or not (TRUE/FALSE).
#' @param trim Whether to remove nodes from the network if they are past the last observation time.
#' @importFrom igraph set_graph_attr
#' @export
#'
#'
extract_networks<-function(data, windowsize, windowshift, directed = FALSE,trim=FALSE, SRI=FALSE){

  #intialize times
  windowstart <- min(data[,4])
  windowend=windowstart+windowsize
  if(windowend>max(data[,4]))print("warnning: the window size is set larger than the observed data.")

  #for every window generate a network
  netlist <- list()
  while (windowstart + windowsize<=max(data[,4])) {

    #subset the data
    df.window<-create.window(data, windowstart, windowend)
    if(trim==TRUE)df.window<-trim_graph(df.window,data,windowstart, windowend)
    Observation.Events <- nrow(df.window)

    #create a network and add it to the list
    g <- create.a.network(df.window, directed = directed, SRI)
    g <- set_graph_attr(g, "nEvents", Observation.Events)
    g <- set_graph_attr(g, "windowstart", windowstart )
    g <- set_graph_attr(g, "windowend", windowend)
    netlist[[length(netlist)+1]] <- g

    #move the window
    windowend = windowend + windowshift
    windowstart = windowstart + windowshift

  }

  print(paste0(length(netlist)," networks extracted"))
  return(netlist)

}

#' Extract networks from a moving window using multiple cores
#'
#' This function will create a time series of networks from a dataframe with relational events and a time stamp, using parallel processing.
#' @param data Dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param windowsize The size of each window in which to generate a network.
#' @param windowshift The amount of time to shift the window when generating networks.
#' @param directed Whether to consider the network as directed or not (TRUE/FALSE).
#' @param cores How many cores should be used.
#' @importFrom parallel makeCluster
#' @importFrom igraph set_graph_attr
#' @export
#'
#'
extract_networks_para<-function(data, windowsize, windowshift, directed = FALSE, cores=2,trim=FALSE, SRI){

  #SRI not implimented yet
  if(SRI==TRUE)print("Warning SRI not yet available for parallel extraction of networks. Using SRI == FALSE.")

  #intialize times
  windowStart <- min(data[,4])
  windowEnd=windowStart+windowsize
  if(windowEnd>max(data[,4]))print("warnning: the window size is set larger than the observed data.")

  #generate a list of windows times
  window.ranges <- data.frame(start=windowStart, end=windowEnd)
  endDay=max(data[,4])
  while(windowEnd<=endDay){
    window.ranges <-  rbind(window.ranges,data.frame(start=windowStart, end=windowStart+windowsize))
    windowStart = windowStart + windowshift
    windowEnd = windowStart + windowsize
  }
  window.ranges<-window.ranges[-1,]

  #setup parallel backend
  cl <- parallel::makeCluster(cores)
  registerDoParallel(cl)

  #generate the networks
  final.net.list<-net.para(data, window.ranges, directed, trim = trim)

  #stop cluster
  parallel::stopCluster(cl)

  #report number of networks extracted
  print(paste0(length(final.net.list)," networks extracted"))

  return(final.net.list)
}

#' Extract networks in parallel using a dataframe of times
#'
#' This function will generate networks in parallel using a dataframe with time constraints.
#' @param data Dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param window.ranges The dataframe containing the start and end times of each window to create a network from.
#' @param directed Whether to consider the networks are directed or not.
#' @export
#'
#'
net.para<-function(data, window.ranges,directed=FALSE,trim){

  #run the processes
  try(finalMatrix <- foreach(i=1:nrow(window.ranges), .export=c("window.net","create.window", "create.a.network","window.net.para"), .packages = c("igraph", "dplyr") ) %dopar%

        net.window.para(data,windowstart = window.ranges[i,1], windowend = window.ranges[i,2], directed, trim=trim)

  )

  return(finalMatrix)
}


#' Extract one network within time constriants
#'
#' This function will generate one network from a dataframe with time constraints.
#' @param data Dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param windowstart The start of the window.
#' @param windowend The end of the window.
#' @param directed Whether to consider the network as directed or not.
#' @importFrom igraph set_graph_attr
#' @export
#'
#'
net.window<-function(data, windowstart, windowend,directed=FALSE, SRI){

  #subset the data
  df.window<-create.window(data, windowstart, windowend)
  Observation.Events <- nrow(df.window)

  #create a network and add it to the list
  g <- create.a.network(df.window, directed = directed, SRI)
  g <- set_graph_attr(g, "nEvents", Observation.Events)
  g <- set_graph_attr(g, "windowstart", windowstart)
  g <- set_graph_attr(g, "windowend", windowend)

  return(g)

}



#' Extract one network within time constriants
#'
#' This function will generate one network from a dataframe with time constraints.
#' @param data Dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param windowstart The start of the window.
#' @param windowend The end of the window.
#' @param directed Whether to consider the network as weighted. (default=FALSE)
#' @importFrom igraph set_graph_attr
#' @export
#'
#'
net.window.para<-function(data, windowstart, windowend,directed=FALSE, trim=FALSE){

  #subset the data
  df.window <- data[data[[4]] >= windowstart & data[[4]] < windowend,]
  if(trim==TRUE)df.window<-trim_graph(df.window,data,windowstart, windowend)
  Observation.Events <- nrow(df.window)

  #create a network and add it to the list
  names(data)<-c("to","from","weight","date")
  elist<-data %>% dplyr::group_by(.dots=c("to","from")) %>% summarise(sum(weight))
  g <- graph_from_data_frame(elist, directed = directed, vertices = NULL)
  if(is.simple(g)==FALSE)g<-simplify(g, edge.attr.comb=list(weight="sum"))

  #add attributes
  g <- igraph::set_graph_attr(g, "nEvents", Observation.Events)
  g <- igraph::set_graph_attr(g, "windowstart", windowstart)
  g <- igraph::set_graph_attr(g, "windowend", windowend)

  return(g)

}


#' Extract network measures from a list of networks
#'
#' This function will estimate network measures from a list of networks.
#' @param netlist List of networks.
#' @param measureFun A function that takes a network as input and returns a single value.
#' @export
#' @importFrom igraph get.graph.attribute
#' @importFrom lubridate ymd
#'
#'
extract_measure_network<-function(netlist, measureFun){

  #store measures
  net.measure <- data.frame(measure=-1,nEvents=-1,windowstart=ymd("2000-01-01"), windowend=ymd("2000-01-01"))

  #extract measures
  if(exists('measureFun', mode='function')){

    for(i in 1:length(netlist)) {
      df.temp <- data.frame(measure=measureFun(netlist[[i]]),
                            nEvents=igraph::get.graph.attribute(netlist[[i]], "nEvents" ),
                            windowstart=igraph::get.graph.attribute(netlist[[i]], "windowstart" ),
                            windowend=igraph::get.graph.attribute(netlist[[i]], "windowend" ))
      net.measure <- rbind(net.measure,df.temp)
    }

  } else {
    print("Error: the measurment function was not found.")
  }

  net.measure<-net.measure[-1,]
  return(net.measure)

}




#' Extract measures from a list of networks when the measure requires comparisons between networks
#'
#' This function will estimate network measures from a list of networks.
#' @param netlist List of networks.
#' @param measureFun A function that takes two networks as input and returns a single value. The first network is the lagged network, and the second is the current network.
#' @param lag At what lag should networks be compared? The number here will be based on the order of the network list generated. E.g., a list of networks generated using a window shift of 10 days, and a lag of 1, would compare networks 10days apart.
#' @param firstNet If TRUE the comparison between networks is always between the current and first network.
#' @export
#' @importFrom igraph get.graph.attribute
#'
#'
extract_lagged_measure_network<-function(netlist, measureFun, lag=1, firstNet){

  #store measures
  net.measure <- data.frame(measure=-1,nEvents=-1,windowstart=ymd("2000-01-01"), windowend=ymd("2000-01-01"))

  if(exists('measureFun', mode='function')){



    for(i in 1:length(netlist)) {

      if(firstNet == FALSE){
        if(i-lag>1){

          df.temp <- data.frame(measure=measureFun(netlist[[i-lag]],netlist[[i]]),
                                nEvents=igraph::get.graph.attribute(netlist[[i]], "nEvents" ),
                                windowstart=igraph::get.graph.attribute(netlist[[i]], "windowstart" ),
                                windowend=igraph::get.graph.attribute(netlist[[i]], "windowend" ))

          net.measure <- rbind(net.measure,df.temp)

        } else {
          df.temp <- data.frame(measure=NA,
                                nEvents=igraph::get.graph.attribute(netlist[[i]], "nEvents" ),
                                windowstart=igraph::get.graph.attribute(netlist[[i]], "windowstart" ),
                                windowend=igraph::get.graph.attribute(netlist[[i]], "windowend" ))

          net.measure <- rbind(net.measure,df.temp)
        }

      } else {

        df.temp <- data.frame(measure=measureFun(netlist[[1]],netlist[[i]]),
                              nEvents=igraph::get.graph.attribute(netlist[[i]], "nEvents" ),
                              windowstart=igraph::get.graph.attribute(netlist[[i]], "windowstart" ),
                              windowend=igraph::get.graph.attribute(netlist[[i]], "windowend" ))

        net.measure <- rbind(net.measure,df.temp)

      }
    }


  } else {
    print("Error: the measurment function was not found.")
  }

  net.measure<-net.measure[-1,]
  return(net.measure)

}



#' Use permutation to extract uncertainty
#'
#' This function will estimate network measures given random permutations on the original data.
#' @param data Dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param windowsize The size of each window in which to generate a network.
#' @param windowshift The amount of time to shift the window when generating networks.
#' @param directed Whether to consider the network as directed or not (TRUE/FALSE).
#' @param measureFun This is a function that takes as an input a igraph network and returns a single value.
#' @param probs numeric vector of probabilities with values in [0,1].
#' @param nperm Number of permutations to perform before extracting network measures.
#' @export
#'
#'
permutation.graph.values<-function(data, windowsize, windowshift, directed = FALSE,measureFun, probs=0.95, nperm=1000, SRI=FALSE){

  #intialize times
  windowstart <- min(data[,4])
  windowend=windowstart+windowsize
  if(windowend>max(data[,4]))print("warnning: the window size is set larger than the observed data.")

  #monitor the progress
  pb <- txtProgressBar(min = as.numeric(windowstart + windowsize), max = as.numeric(max(data[,4])), style = 3)

  #for every window generate a network
  perm.values.high <- vector()
  perm.values.low <- vector()
  while (windowstart + windowsize<=max(data[,4])) {

    #subset the data
    df.window<-create.window(data, windowstart, windowend)
    Observation.Events <- nrow(df.window)

    #perform permutations
    perm.out<-perm.interactions(df.window, measureFun, directed, probs=probs,nperm= nperm, SRI=SRI)

    #record the high and low estimates
    perm.values.high[[length(perm.values.high)+1]] <- perm.out[2]
    perm.values.low[[length(perm.values.low)+1]] <- perm.out[1]

    #move the window
    windowend = windowend + windowshift
    windowstart = windowstart + windowshift

    #update progress bar
    setTxtProgressBar(pb,  as.numeric(windowend) )

  }

  perm.df<-data.frame(CI.low=perm.values.low,CI.high=perm.values.high)

  return(perm.df)

}




#' Perform permutation
#'
#' This function will permute a network by randomly switching individuals within events.
#' @param data Dataframe with relational data in the first two rows, with weights in the thrid row, and a time stamp in the fourth row. Note: time stamps should be in ymd or ymd_hms format. The lubridate package can be very helpful in organizing times.
#' @param measureFun This is a function that takes as an input a igraph network and returns a single value.
#' @param directed Whether to consider the network as directed or not (TRUE/FALSE).
#' @param nperm Number of permutations to perform before extracting network measures.
#' @param probs numeric vector of probabilities with values in [0,1].
#' @export
#'
#'
perm.interactions <- function(data, measureFun, directed=FALSE, nperm=1000, probs=0.95, SRI){

  net.list <- list(create.a.network(data, directed,SRI=SRI))
  Perm.measure<-vector()

  for(i in 1:nperm){

    no.loops= FALSE

    #choose to or from grooming to permute
    if(0.5 > runif(1)){

      while(no.loops == FALSE){

        #choose two individuals to switch
        rows.to.switch <- sample(1:nrow(data),2,F)

        #record old order
        old.order <- data$to
        new.order <- data$to

        #update order
        new.order[rows.to.switch[1]] <- old.order[rows.to.switch[2]]
        new.order[rows.to.switch[2]] <- old.order[rows.to.switch[1]]

        #check to make sure there are no self loops
        if(sum(as.character(data$from)==as.character(new.order) )==0){

          data$to <- new.order
          NewData<- data
          no.loops=TRUE

        }
      }

    }  else {
      while(no.loops == FALSE){

        #choose two individuals to switch
        rows.to.switch <- sample(1:nrow(data),2,F)

        #record old order
        old.order <- data$from
        new.order <- data$from

        #update order
        new.order[rows.to.switch[1]] <- old.order[rows.to.switch[2]]
        new.order[rows.to.switch[2]] <- old.order[rows.to.switch[1]]

        #check to make sure there are no self loops
        if(sum(as.character(new.order)==as.character(data$to) )==0){

          data$from <- new.order
          NewData<- data
          no.loops=TRUE

        }
      }
    }

    #Create graph in order to get the measure
    Perm.network <- create.a.network(NewData, directed, SRI = SRI)

    # Get measure
    Perm.measure[length(Perm.measure)+1]<- measureFun(Perm.network)

  }

  probs.left<-1-probs
  return(quantile(Perm.measure, probs = c( (0+probs.left/2), (1-probs.left/2) ), na.rm=T))
}



#' Trim nodes when taking network measures.
#'
#' This function removes node from the network when they are beyond their min and max observed times, then takes the network measure.
#' @param nodevalues Output from the nodeTS function.
#' @param data The events dataframe used in the nodeTS function.
#' @importFrom dplyr select
#' @importFrom dplyr filter
#' @export
#'
trim_graph<-function(df.window, data, windowstart, windowend){

  #ensure the names of the first four columns
  names(data)[1:4]<- c("from","to","weight","date")

  #which names to keep
  names.kept<-unique( c(df.window[,1],df.window[,2]) )

  #Initialize trimed dataframes with important vars
  #df.trim<- data.frame(remove=rep(NA,nrow(nodevalues)))

  #loop through each ID and trim based on min and max date observed
  for(i in 1:length(names.kept)){

    #determine the min and max dates the focal was seen
    df.temp <- data %>% filter(from == names.kept[i] | to == names.kept[i])
    min.date<-min(df.temp$date)
    max.date<-max(df.temp$date)

    #check if individual was seen before/after this particular window
    if( (min.date<=windowstart & max.date>=windowend) == FALSE){

      #remove this individual from the window
      df.window<-df.window[df.window[,1]!=names.kept[i],]
      df.window<-df.window[df.window[,2]!=names.kept[i],]
    }

  }

  return(df.window)

}


