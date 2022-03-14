#PJG: DEBUG Remove when complete
macro __FUNCTION__()
    return :($(esc(Expr(:isdefined, :var"#self#"))) ? $(esc(:var"#self#")) : nothing)
end

# ----------------------------------------------------
# Positive Semidefinite Cone
# ----------------------------------------------------

dim(K::PSDCone{T})    where {T} = K.dim     #number of elements
degree(K::PSDCone{T}) where {T} = K.n       #side dimension, M \in \mathcal{S}^{n×n}


function update_scaling!(
    K::PSDCone{T},
    s::AbstractVector{T},
    z::AbstractVector{T},
) where {T}

    (S,Z) = map(m->Symmetric(_mat(m,K)), (s,z))

    f = K.work

    #compute Cholesky factors
    f.cholS = cholesky(S, check = true)
    f.cholZ = cholesky(Z, check = true)

    #explicit factors
    f.L1    = f.cholS.L
    f.L2    = f.cholZ.L

    #product L2'L1, hugely wasteful of memory here
    M = f.L2'*f.L1

    #SVD of M.   Requires further workspace
    f.SVD = svd(M)

    #explicit extraction of factors.  Maybe not needed
    f.U = f.SVD.U
    f.λ = f.SVD.S
    f.V = f.SVD.V

    #assemble R and Rinv.   Maybe not needed
    isqrtλ = Diagonal(inv.(sqrt.(f.λ)))
    f.R    = f.L1*f.V*isqrtλ
    f.Rinv = isqrtλ*f.U'*f.L2'

    return nothing
end



#configure cone internals to provide W = I scaling
function set_identity_scaling!(
    K::PSDCone{T}
) where {T}

    K.W .= I(K.n)

    return nothing
end

function get_diagonal_scaling!(
    K::PSDCone{T},
    diagW2::AbstractVector{T}
) where {T}

    print("Placeholder at :", @__FUNCTION__, "\n")
    @. diagW2 = -K.w^2

    return nothing
end

# returns x = λ ∘ λ for the SDP cone
function λ_circ_λ!(
    K::PSDCone{T},
    x::AbstractVector{T}
) where {T}

    #We have Λ = Diagonal(K.λ), so
    #λ ∘ λ should map to Λ.^2
    x .= zero(T)

    #same as X = Λ*Λ
    x[1:(K.n+1):end] .= K.λ^2

end

# implements x = y ∘ z for the SDP cone
#PJG Bottom p5, CVXOPT
function circ_op!(
    K::PSDCone{T},
    x::AbstractVector{T},
    y::AbstractVector{T},
    z::AbstractVector{T}
) where {T}

    #make square views
    (X,Y,Z) = map(m->_mat(m,K), (x,y,z))

    X  .= Y*Z + Z*Y
    X .*= 0.5

    return nothing
end

# implements x = λ \ z for the SDP cone
# PJG, Top page 14, \S5, CVXOPT
function λ_inv_circ_op!(
    K::PSDCone{T},
    x::AbstractVector{T},
    z::AbstractVector{T}
) where {T}

    #make square views
    (X,Z) = map(m->_mat(m,K), (x,z))

    # PJG : should only really need to compute
    # a triangular part of this matrix.  Keeping
    # like this for now until something works
    for i = 1:K.n
        for j = 1:K.n
            X[i,j] = 2*Z[i,j]/(K.λ[i] + K.λ[j])
        end
    end

    return nothing
end

# implements x = y \ z for the SDP cone
# PJG, Top page 14, \S5, CVXOPT
function inv_circ_op!(
    K::PSDCone{T},
    x::AbstractVector{T},
    y::AbstractVector{T},
    z::AbstractVector{T}
) where {T}

    #make square views
    (X,Y,Z) = map(m->_mat(m,K), (x,y,z))

    # X should be the solution to (YX + XY)/2 = Z

    # PJG: or general arguments this requires solution to a symmetric
    # Sylvester equation.  Throwing an error here since I do not think
    # the inverse of the ∘ operator is ever required for general arguments,
    # and solving this equation is best avoided.

    error("This function not implemented and should never be reached.")

    return nothing
end

# place vector into SDP cone

function shift_to_cone!(
    K::PSDCone{T},
    z::AbstractVector{T}
) where{T}

    Z = _mat(z,K)
    α = eigvals(Symmetric(Z),1:1)[1]  #min eigenvalue

    if(α < eps(T))
        #done in two stages since otherwise (1-α) = -α for
        #large α, which makes z exactly 0. (or worse, -0.0 )
        add_scaled_e!(K,z,-α)
        add_scaled_e!(K,z,one(T))
    end

    return nothing
end


# implements y = αWx + βy for the PSD cone
function gemv_W!(
    K::PSDCone{T},
    is_transpose::Bool,
    x::AbstractVector{T},
    y::AbstractVector{T},
    α::T,
    β::T
) where {T}

  (X,Y) = map(m->_mat(m,K), (x,y))

  β == 0 ? y .= 0 : y .*= β

  R   = K.work.R

  #PJG: needs unit test since only one of these
  #cases is explicitly described in the CVXOPT paper
  if is_transpose
      Y .+= α*(R*X*R')  #W^T*x
  else
      Y .+= α*(R'*X*R)  #W*x
  end

  return nothing
end

# implements y = αW^{-1}x + βy for the psd cone
function gemv_Winv!(
    K::PSDCone{T},
    is_transpose::Bool,
    x::AbstractVector{T},
    y::AbstractVector{T},
    α::T,
    β::T
) where {T}

    (X,Y) = map(m->_mat(m,K), (x,y))

    β == 0 ? y .= 0 : y .*= β

    Rinv = K.work.Rinv

    #PJG: needs unit test since only one of these
    #cases is explicitly described in the CVXOPT paper
    if is_transpose
        Y .+= α*(Rinv*X*Rinv')  #W^{-T}*x
    else
        Y .+= α*(Rinv'*X*Rinv)  #W^{-1}*x
    end

    return nothing
end


# implements y = (W^TW)^{-1}x
function mul_WtWinv!(
    K::PSDCone{T},
    x::AbstractVector{T},
    y::AbstractVector{T}
) where {T}

    #PJG: needs unit test?   Aliasing not allowed
    #Also check aliasing in other cones, esp. SOC
    gemv_Winv!(K,true,y,y,one(T),zero(T))
    gemv_Winv!(K,false,x,y,one(T),zero(T))

    return nothing
end

# implements y = W^TW^x
function mul_WtW!(
    K::PSDCone{T},
    x::AbstractVector{T},
    y::AbstractVector{T}
) where {T}

    #PJG: needs unit test?
    gemv_W!(K,false,y,y,one(T),zero(T))
    gemv_W!(K,true,x,y,one(T),zero(T))

    return nothing
end

# implements y = y + αe for the SDP cone
function add_scaled_e!(
    K::PSDCone{T},
    x::AbstractVector{T},
    α::T
) where {T}

    #same as X .+= eye(K.n)
    x[1:(K.n+1):end] .+= α

    return nothing
end


##return maximum allowable step length while remaining in the psd cone
function step_length(
    K::PSDCone{T},
    dz::AbstractVector{T},
    ds::AbstractVector{T},
     z::AbstractVector{T},
     s::AbstractVector{T}
) where {T}

    #PJG: this inv sqrt is repeatng, and \lambda is
    #living in two places at the moment
    Λisqrt = Diagonal(inv.(sqrt.(K.work.λ)))
    ΔZ = Symmetric(_mat(dz,K))
    ΔS = Symmetric(_mat(ds,K))

    #PJG: DEBUG: alloc here requires removal
    d   = similar(dz)
    Δ   = Symmetric(_mat(d,K))

    #d = Δz̃ = WΔz
    gemv_W!(K, false, dz, d, one(T), zero(T))
    αz = _step_length_psd_component(K,Δ,Λisqrt)

    #d = Δs̃ = W^{-T}Δs
    gemv_Winv!(K, true, ds, d, one(T), zero(T))
    αs = _step_length_psd_component(K,Δ,Λisqrt)

    α = min(αz,αs)

    return α
end


function _step_length_psd_component(
    K,
    Δ::Symmetric{T},
    Λisqrt::Diagonal{T}
) where {T}

    #PJG:passing K since it probably need a workspace
    M = Symmetric(Λisqrt*Δ*Λisqrt)

    γ = eigvals(M,1:1)[1] #minimum eigenvalue
    α = γ < 0 ? inv(-γ) : inv(eps(T))
    return α

end

# -------------------
# internal utilities for this cone
#--------------------

#make a matrix view from a vectorized input
_mat(x::AbstractVector{T},K::PSDCone{T}) where {T} = reshape(x,K.n,K.n)
