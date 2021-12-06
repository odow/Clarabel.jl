# -------------------------------------
# User definable settings
# -------------------------------------
mutable struct Settings{T <: AbstractFloat}
    max_iter::DefaultInt
    verbose::Bool
    tol_gap_abs::T
    tol_gap_rel::T
    tol_feas::T
    direct_kkt_solver::Bool

    function Settings{T}(;
        max_iter = 50,
        verbose = true,
        tol_gap_abs = 1e-7,
        tol_gap_rel = 1e-6,
        tol_feas    = 1e-5,
        direct_kkt_solver = true) where {T}

        new(max_iter,verbose,tol_gap_abs,tol_gap_rel,tol_feas,direct_kkt_solver)

    end
end

# Default to DefaultFloat type for reals
Settings(args...; kwargs...) = Settings{DefaultFloat}(args...; kwargs...)