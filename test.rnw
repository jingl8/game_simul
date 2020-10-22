####################
# a very simple loop
#
# compute squares, cubes, and fourths of numbers 1-12
# save all the results in a matrix
####################

data<-matrix(0,nrow=12,ncol=4)
for(i in 1:12){
  data[i,1]<-i^1
  data[i,2]<-i^2
  data[i,3]<-i^3
  data[i,4]<-i^4
  }
  
colnames(data) <- c("first","squared","cubed","fourth")
data
  
 ## notice that the lines above that over-write the columns of the data matrix
 ## look very similar
 ## we could have used a small loop to avoid repetition  

# below, I align the open and close braces
# to help me keep track of the loops
# I also chose index letters that are mnemonics for 'row' and 'column'
data2<-matrix(0,nrow=12,ncol=4)
for(r in 1:12) {
	for(c in 1:4) {
	  data2[r,c]<-i^c
    }
}

colnames(data2) <- c("first","squared","cubed","fourth")
data2

# Note that these loops work because the sequences match the built-in R indexes 
# in other words, we write to row r and column c, and I designed the exercise to make
# the match between the loop index and the R position indexes simple.
# If I wanted to display square roots and squares, those powers are 1/2 and 2, 
# and so I need slightly more complicated code.


data3<-matrix(0,nrow=12,ncol=3)
powers<-c(1,1/2,2)
for(r in 1:12) {
	for(c in 1:3) {
	  data3[r,c]<-r^(powers[c])
    }
}

colnames(data3) <- c("x","sqrt(x)","x^2")
data3


########################################
# one more use of loops:
# begin to pay attention to variance in 
# regression parameter estimates
########################################


# generate data from known data-generating process

x<-runif(200,0,1)

y<-5+2*x+rnorm(200,0,.15)

plot(x,y)
abline(lm(y~x),col="red")


lm(y~x)

# What if we repeatedly created y with known slope and intercept plus noise, and kept track of 
#  the regression parameter estimates (intercept and slope)?

# recall that rnorm(x,m,s) draws x times from a normal distribution with mean m and std dev s

inter_low<-c()
slope_low<-c()

for (s in 1:500){
	x<-runif(200,0,1)
	y<-5+2*x+rnorm(200,0,.15)
	inter_low[s]<-coef(lm(y~x))[1]
	slope_low[s]<-coef(lm(y~x))[2]
 }
 
par(mfrow=c(2,2))
hist(inter_low,main="lower variance error term",xlab="intercept estimate")
hist(slope_low,main="lower variance error term",xlab="slope estimate")

mean(slope_low)
sd(slope_low) 
 
mean(inter_low)
sd(inter_low) 
 
 # Repeat one more time, but with more noise
 
 inter_hi<-c()
 slope_hi<-c()
 
 for (s in 1:500){
 	x<-runif(200,0,1)
 	y<-5+2*x+rnorm(200,0,.5)
 	inter_hi[s]<-coef(lm(y~x))[1]
 	slope_hi[s]<-coef(lm(y~x))[2]
  }
  
  hist(inter_hi,main="higher variance error term",xlab="intercept estimate")
  hist(slope_hi, main="higher variance error term",xlab="slope estimate")

mean(slope_hi)
sd(slope_hi) 

mean(inter_hi)
sd(inter_hi)
  
