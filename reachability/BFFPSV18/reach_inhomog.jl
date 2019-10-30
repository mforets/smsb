# projection matrix onto a given block
# for instance, Π([1, 2], 3) is: 
# [1 0 0]
# [0 1 0]
@inline Π(bi::AbstractVector{Int}, n::Int) = sparse(1:length(bi), bi, ones(Float64, length(bi)), length(bi), n)

# this is a "selective" decomposition since the number of row_blocks may be smaller than then number of column_blocks
# FIXME call decompose directly (?)
# Moreover, we may be able to specialize this function for the case where ST is an Interval
@inline function _decompose_input!(Whatk, n, row_blocks, U, ST)
    @inbounds for (i, bi) in enumerate(row_blocks)
        Whatk[i] = overapproximate(Π(bi, n) * U, ST)
    end
end

@inline function _overapproximate_input(Whatk_i, ϕpowerk, bi, U, ST)
    return overapproximate(Whatk_i ⊕ ϕpowerk[bi, :] * U, ST)
end

# NOTE: ϕpowerk[bi, :] * U has 1 x m dimensions if m is the number of column blocks
# we may as well compute the interval overapproximation of this set by taking the
# interval-based linear maps and the interval-based sums with a possible (?) decrease
# in accuracy
@inline function _overapproximate_input(Whatk_i, ϕpowerk, bi, U, ST::Type{<:Interval})
    Vhatk_i = overapproximate(ϕpowerk[bi, :] * U, ST)
    return Interval(Whatk_i.dat + Vhatk_i.dat)
end

# ====================
# x' = Ax + u, u in U
# ====================
# GENERIC, constant input
function reach_inhomog!(res, ϕ, Xhat0, U, δ, N, vars, block_indices, row_blocks, column_blocks, NUM, ST)

    # store first element
    ti, tf = 0.0, δ
    R0 = ReachSet(CartesianProductArray(Xhat0[block_indices]), ti, tf)
    res[1] = SparseReachSet(R0, vars)

    # cache matrix
    ϕpowerk = copy(ϕ)
    ϕpowerk_cache = similar(ϕ)

    # preallocate buffer for each row-block
    buffer = Vector{LazySets.LinearMap{NUM, ST, NUM, Matrix{NUM}}}(undef, length(column_blocks))

    # preallocate overapproximated Minkowski sum for each row-block
    Xhatk = Vector{ST}(undef, length(row_blocks))

    # preallocate accumulated inputs and decompose it
    Whatk = Vector{ST}(undef, length(row_blocks))
    _decompose_input!(Whatk, size(ϕ, 1), row_blocks, U, ST)

    @inbounds for k in 2:N
        for (i, bi) in enumerate(row_blocks) # loop over row-blocks of interest
            for (j, bj) in enumerate(column_blocks) # loop over all column-blocks
                buffer[j] = ϕpowerk[bi, bj] * Xhat0[j]
            end
            Xhatk[i] = overapproximate(MinkowskiSumArray(buffer) ⊕ Whatk[i], ST)
        end
        ti = tf
        tf += δ
        Rk = ReachSet(CartesianProductArray(copy(Xhatk)), ti, tf)
        res[k] = SparseReachSet(Rk, vars)

        # update the input set
        for (i, bi) in enumerate(row_blocks)
            Whatk[i] = _overapproximate_input(Whatk[i], ϕpowerk, bi, U, ST)
        end
        
        # update matrices
        mul!(ϕpowerk_cache, ϕpowerk, ϕ)
        copyto!(ϕpowerk, ϕpowerk_cache)
    end
    return res
end

# INTERVAL
function reach_inhomog!(res, ϕ, Xhat0, U, δ, N, vars, block_indices, row_blocks, column_blocks, NUM, ST::Type{<:Interval})

    # store first element
    ti, tf = 0.0, δ
    R0 = ReachSet(CartesianProductArray(Xhat0[block_indices]), ti, tf)
    res[1] = SparseReachSet(R0, vars)

    # cache matrix
    ϕpowerk = copy(ϕ)
    ϕpowerk_cache = similar(ϕ)

    # preallocate overapproximated Minkowski sum for each row-block
    Xhatk = Vector{ST}(undef, length(row_blocks))

    # preallocate accumulated inputs and decompose it
    Whatk = Vector{ST}(undef, length(row_blocks))
    _decompose_input!(Whatk, size(ϕ, 1), row_blocks, U, ST)

    @inbounds for k in 2:N
        for (i, bi) in enumerate(row_blocks) # loop over row-blocks of interest
            Xhatk[i] = Interval(zero(NUM), zero(NUM))
            for (j, bj) in enumerate(column_blocks) # loop over all column-blocks
                Xhatk[i] += Interval(ϕpowerk[bi[1], bj[1]] * Xhat0[j].dat)
            end
            Xhatk[i] += Whatk[i]
        end
        ti = tf
        tf += δ
        Rk = ReachSet(CartesianProductArray(copy(Xhatk)), ti, tf)
        res[k] = SparseReachSet(Rk, vars)

        # update the input set
        for (i, bi) in enumerate(row_blocks)
            Whatk[i] = _overapproximate_input(Whatk[i], ϕpowerk, bi, U, ST)
        end

        mul!(ϕpowerk_cache, ϕpowerk, ϕ)
        copyto!(ϕpowerk, ϕpowerk_cache)
    end
    return res
end
