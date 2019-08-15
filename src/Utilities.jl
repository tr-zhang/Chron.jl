## --- Constructing arrays

    # Construct linearly spaced array with n points between l and u
    # (linspace replacement )
    if VERSION>=v"0.7"
        function linsp(l::Number,u::Number,n::Number)
            return range(l,stop=u,length=n)
        end
    else
        function linsp(l::Number,u::Number,n::Number)
            return linspace(l,u,n)
        end
    end

## --- Weighted means

    # Calculate a weigted mean, including MSWD, with MSWD correction to uncertainty.
    function gwmean(x, sigma)
        n = length(x)
        s1 = 0.0; s2 = 0.0; s3 = 0.0

        if n==1
            wx = x[1]
            mswd = 0
            wsigma = sigma[1]
        else
            for i=1:n
                s1 += x[i] / (sigma[i]*sigma[i])
                s2 += 1 / (sigma[i]*sigma[i])
            end
            wx = s1/s2

            for i=1:n
                s3 += (x[i] - wx) * (x[i] - wx) / (sigma[i]*sigma[i])
            end
            mswd = s3 / (n-1)
            wsigma = sqrt(mswd/s2)
        end
        return wx, wsigma, mswd
    end

    # Calculate a weigted mean, including MSWD, but without MSWD correction to uncertainty
    function awmean(x, sigma)
        n = length(x)
        s1 = 0.0; s2 = 0.0; s3 = 0.0

        if n==1
            wx = x[1]
            mswd = 0
            wsigma = sigma[1]
        else
            for i=1:n
                s1 += x[i] / (sigma[i]*sigma[i])
                s2 += 1 / (sigma[i]*sigma[i])
            end
            wx = s1/s2

            for i=1:n
                s3 += (x[i] - wx) * (x[i] - wx) / (sigma[i]*sigma[i])
            end
            mswd = s3 / (n-1)
            wsigma = sqrt(1.0/s2)
        end
        return wx, wsigma, mswd
    end

## --- Interpolation

    # Linearly interpolate vector y at index i, returning outboundsval if out of bounds
    function linterp_at_index(y::AbstractArray, i::Number, outboundsval=NaN)
        if i > 1 && i < length(y)
            i_below = floor(Int, i)
            i_above = i_below + 1
            f = i - i_below
            return @inbounds Float64(f*y[i_above] + (1-f)*y[i_below])
        else
            return Float64(outboundsval)
        end
    end

    # Linear interpolation, sorting inputs
    if VERSION>v"0.7"
        function linterp1s(x,y,xq)
            sI = sortperm(x) # indices to construct sorted array
            itp = LinearInterpolation(x[sI], y[sI], extrapolation_bc = Line())
            yq = itp(xq) # Interpolate value of y at queried x values
            return yq
        end
    else
        function linterp1s(x,y,xq)
            sI = sortperm(x) # indices to construct sorted array
            itp = interpolate((x[sI],), y[sI], Gridded(Linear()))
            yq = itp[xq] # Interpolate value of y at queried x values
            return yq
        end
    end

    # linear interpolation
    if VERSION>v"0.7"
        function linterp1(x,y,xq)
            itp = LinearInterpolation(x,y, extrapolation_bc = Line())
            yq = itp(xq) # Interpolate value of y at queried x values
            return yq
        end
    else
        function linterp1(x,y,xq)
            itp = interpolate((x,),y, Gridded(Linear()))
            yq = itp[xq] # Interpolate value of y at queried x values
            return yq
        end
    end

## --- Working with Gaussian distributions

    # Probability density function of the Normal (Gaussian) distribution
    function normpdf(mu::Number,sigma::Number,x::Number)
        return exp(-(x-mu)*(x-mu) / (2*sigma*sigma)) / (sqrt(2*pi)*sigma)
    end

    # Fast Log Likelihood corresponding to a Normal (Gaussian) distribution
    function normpdf_LL(mu::Number,sigma::Number,x::Number)
        return -(x-mu)*(x-mu) / (2*sigma*sigma)
    end
    export normpdf_LL

    # Cumulative density function of the Normal (Gaussian) distribution
    # Not precise enough for many uses, unfortunately
    function normcdf(mu::Number,sigma::Number,x::Number)
        return 0.5 + erf((x-mu) / (sigma*sqrt(2))) / 2
    end

    # How far away from the mean (in units of sigma) should we expect proportion
    # F of the samples to fall in a Normal (Gaussian) distribution
    function norm_quantile(F::Number)
        return sqrt(2)*erfinv(2*F-1)
    end

    # How dispersed (in units of sigma) should we expect a sample of N numbers
    # drawn from a Normal (Gaussian) distribution to be?
    function norm_width(N)
        F = 1 - 1/(N+1)
        return 2*norm_quantile(F)
    end

## --- Drawing from distributions

    # Draw random numbers from a distribution specified by a vector of points
    # defining the PDF curve
    function draw_from_distribution(dist::Array{Float64}, n::Int)
        # Draw n random numbers from the distribution 'dist'
        x = Array{Float64}(undef,n)
        dist_ymax = maximum(dist)
        dist_xmax = length(dist)-1.0

        for i=1:n
            while true
                # Pick random x value
                rx = rand() * dist_xmax
                # Interpolate corresponding distribution value
                f = floor(Int,rx)
                y = dist[f+2]*(rx-f) + dist[f+1]*(1-(rx-f))
                # See if x value is accepted
                ry = rand() * dist_ymax
                if (y > ry)
                    x[i] = rx / dist_xmax
                    break
                end
            end
        end
        return x
    end

    # Fill an existing variable with random numbers from a distribution specified
    # by a vector of points defining the PDF curve
    function fill_from_distribution(dist::Array{Float64}, x::Array{Float64})
        # Fill the array x with random numbers from the distribution 'dist'
        dist_ymax = maximum(dist)
        dist_xmax = length(dist)-1.0

        for i=1:length(x)
            while true
                # Pick random x value
                rx = rand() * dist_xmax
                # Interpolate corresponding distribution value
                f = floor(Int,rx)
                y = dist[f+2]*(rx-f) + dist[f+1]*(1-(rx-f))
                # See if x value is accepted
                ry = rand() * dist_ymax
                if (y > ry)
                    x[i] = rx / dist_xmax
                    break
                end
            end
        end
    end


## --- Fitting non-Gaussian distributions

    # Two-sided linear exponential distribution joined by an atan sigmoid.
    function bilinear_exponential(x,p)
        # If to a normal-esque PDF, parameters p roughly correspond to:
        # p[1] = pre-exponential (normaliation constant)
        # p[2] = mean (central moment)
        # p[3] = variance
        # p[4] = sharpness
        # p[5] = skew
        xs = (x .- p[2])./p[3] # X scaled by mean and variance
        v = 1/2 .- atan.(xs)./pi # Sigmoid (positive on LHS)
        f = p[1] .* exp.((p[4].^2).*(p[5].^2).*xs.*v .- (p[4].^2)./(p[5].^2).*xs.*(1 .- v))
        return f
    end

    # Log of two-sided linear exponential distribution joined by an atan sigmoid.
    function bilinear_exponential_LL(x,p)
        # If to a normal-esque PDF, parameters p roughly correspond to:
        # p[1] = pre-exponential (normaliation constant)
        # p[2] = mean (central moment)
        # p[3] = variance
        # p[4] = sharpness
        # p[5] = skew
        xs = (x-p[2,:])./p[3,:] # X scaled by mean and variance
        v = 1/2 .- atan.(xs)./pi # Sigmoid (positive on LHS)
        f = log.(p[1,:]) + (p[4,:].^2).*(p[5,:].^2).*xs.*v .- (p[4,:].^2)./(p[5,:].^2).*xs.*(1 .- v)
        return f
    end

    # Interpolate log likelihood from an array
    function interpolate_LL(x,p)
        ll = Array{Float64}(undef, size(x))
        for i = 1:length(x)
            ll[i] = linterp_at_index(p[:,i], x[i], -Inf)
        end
        return ll
    end

    # # Two-sided linear exponential distribution joined by an atan sigmoid.
    # function biparabolic_exponential_LL(x,p)
    #     # If to a normal-esque PDF, parameters p roughly correspond to:
    #     # p[1] = pre-exponential (normaliation constant)
    #     # p[2] = mean (central moment)
    #     # p[3] = standard deviation
    #     # p[4] = sharpness
    #     # p[5] = skew
    #     xs = (x-p[2])./p[3] # X scaled by mean and variance
    #     v = 1/2-atan.(xs)/pi # Sigmoid (positive on LHS)
    #     f = p[1] .* exp.(-(p[4].^2).*(p[5].^2).*(xs.^2).*v -(p[4].^2)./(p[5].^2).*(xs.^2).*(1-v))
    #     return f
    # end
    #
    # # Log of two-sided parabolic exponential distribution joined by an atan sigmoid.
    # function biparabolic_exponential_LL(x,p)
    #     # If to a normal-esque PDF, parameters p roughly correspond to:
    #     # p[1] = pre-exponential (normaliation constant)
    #     # p[2] = mean (central moment)
    #     # p[3] = standard deviation
    #     # p[4] = sharpness
    #     # p[5] = skew
    #     xs = (x-p[2,:])./p[3,:] # X scaled by mean and variance
    #     v = 1/2-atan.(xs)/pi # Sigmoid (positive on LHS)
    #     f = log.(p[1,:]) + (p[4,:].^2).*(p[5,:].^2).*(xs.^2).*v - (p[4,:].^2)./(p[5,:].^2).*(xs.^2).*(1-v)
    #     return f
    # end

## --- Various other utility functions

    # Returns a vector of bin centers if given a vector of bin edges
    function cntr(edges)
        centers = (edges[1:end-1]+edges[2:end])/2
        return centers
    end

    # Return percentile of an array along a specified dimension
    function pctile(A,p;dim=0)
        s = size(A)
        if dim==2
            out = Array{typeof(A[1])}(undef,s[1])
            for i=1:s[1]
                t = .~ isnan.(A[i,:])
                out[i] = percentile(A[i,t],p)
            end
        elseif dim==1
            out = Array{typeof(A[1])}(undef,s[2])
            for i=1:s[2]
                t = .~ isnan.(A[:,i])
                out[i] = percentile(A[t,i],p)
            end
        else
            out = percentile(A,p)
        end
        return out
    end

    function nanminimum(A;dim=0)
        s = size(A)
        if dim==2
            out = Array{typeof(A[1])}(undef,s[1])
            for i=1:s[1]
                t = .~ isnan.(A[i,:])
                out[i] = minimum(A[i,t])
            end
        elseif dim==1
            out = Array{typeof(A[1])}(undef,s[2])
            for i=1:s[2]
                t = .~ isnan.(A[:,i])
                out[i] = minimum(A[t,i])
            end
        else
            t = .~ isnan.(A)
            out = minimum(A[t])
        end
        return out
    end

    function nanmaximum(A;dim=0)
        s = size(A)
        if dim==2
            out = Array{typeof(A[1])}(undef,s[1])
            for i=1:s[1]
                t = .~ isnan.(A[i,:])
                out[i] = maximum(A[i,t])
            end
        elseif dim==1
            out = Array{typeof(A[1])}(undef,s[2])
            for i=1:s[2]
                t = .~ isnan.(A[:,i])
                out[i] = maximum(A[t,i])
            end
        else
            t = .~ isnan.(A)
            out = maximum(A[t])
        end
        return out
    end

    function nanrange(A;dim=0)
        s = size(A)
        if dim==2
            out = Array{typeof(A[1])}(undef,s[1])
            for i=1:s[1]
                t = .~ isnan.(A[i,:])
                extr = extrema(A[i,t])
                out[i] = extr[2] - extr[1]
            end
        elseif dim==1
            out = Array{typeof(A[1])}(undef,s[2])
            for i=1:s[2]
                t = .~ isnan.(A[:,i])
                extr = extrema(A[t,i])
                out[i] = extr[2] - extr[1]
            end
        else
            t = .~ isnan.(A)
            extr = extrema(A[t])
            out = extr[2] - extr[1]
        end
        return out
    end

    function nanmean(A;dim=0)
        s = size(A)
        if dim==2
            out = Array{typeof(A[1])}(undef,s[1])
            for i=1:s[1]
                t = .~ isnan.(A[i,:])
                out[i] = mean(A[i,t])
            end
        elseif dim==1
            out = Array{typeof(A[1])}(undef,s[2])
            for i=1:s[2]
                t = .~ isnan.(A[:,i])
                out[i] = mean(A[t,i])
            end
        else
            t = .~ isnan.(A)
            out = mean(A[t])
        end
        return out
    end

    function nanstd(A;dim=0)
        s = size(A)
        if dim==2
            out = Array{typeof(A[1])}(undef,s[1])
            for i=1:s[1]
                t = .~ isnan.(A[i,:])
                out[i] = std(A[i,t])
            end
        elseif dim==1
            out = Array{typeof(A[1])}(undef,s[2])
            for i=1:s[2]
                t = .~ isnan.(A[:,i])
                out[i] = std(A[t,i])
            end
        else
            t = .~ isnan.(A)
            out = std(A[t])
        end
        return out
    end

    function nanmedian(A;dim=0)
        s = size(A)
        if dim==2
            out = Array{typeof(A[1])}(undef,s[1])
            for i=1:s[1]
                t = .~ isnan.(A[i,:])
                out[i] = median(A[i,t])
            end
        elseif dim==1
            out = Array{typeof(A[1])}(undef,s[2])
            for i=1:s[2]
                t = .~ isnan.(A[:,i])
                out[i] = median(A[t,i])
            end
        else
            t = .~ isnan.(A)
            out = median(A[t])
        end
        return out
    end

    # Return the index of the closest value of Target for each value in Source
    function findclosest(source, target)
        index=Array{Int64}(undef,size(source))
        for i=1:length(source)
            index[i]=argmin((target .- source[i]).^2)
        end
        return index
    end

    # Return the index of the closest value of the vector 'target' below each
    # value in 'source'
    function findclosestbelow(source, target)
        index=Array{Int64}(undef,size(source))
        for i=1:length(source)
            t = findall(target .< source[i])
            ti = argmin((target[t] .- source[i]).^2)
            index[i] = t[ti]
        end
        return index
    end

    # Return the index of the closest value of the vector 'target' above each
    # value in 'source'
    function findclosestabove(source, target)
        index=Array{Int64}(undef,size(source))
        for i=1:length(source)
            t = findall(target .> source[i])
            ti = argmin((target[t] .- source[i]).^2)
            index[i] = t[ti]
        end
        return index
    end


## --- Other

    # Direct system() access without stripping special characters like Julia's
    # rather protective "run()".
    function system(cmdstr)
        return ccall((:system,), Int, (Cstring,), cmdstr)
    end
    export system

    if VERSION>=v"1.0"
        function linspace(l::Number,u::Number,n::Number)
            return range(l,stop=u,length=n)
        end
        export linspace

        function repmat(A::AbstractArray, vert::Integer)
            return repeat(A, outer=vert)
        end
        function repmat(A::AbstractArray, vert::Integer, horiz::Integer)
            return repeat(A, outer=(vert, horiz))
        end
        export repmat

        function contains(haystack::AbstractString, needle::Union{AbstractString,Regex,AbstractChar})
            return occursin(needle::Union{AbstractString,Regex,AbstractChar}, haystack::AbstractString)
        end
        export contains
    end

## --- End of File
