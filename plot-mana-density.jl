datadir = "/home/christopher/work/2019-10-MAGIC/data"
figdir = "/home/christopher/work/2019-10-MAGIC/MAGICPAPER00/figures"
krylov_L = 6


nb = "MAGICPAPER00_plot-mana-density"
orderparameter = "\\langle Z + Z^\\dagger \\rangle"

using Serialization
using DataFrames

using Arpack
using LinearAlgebra
using OffsetArrays
using Combinatorics
using ProgressMeter
using PyPlot
using PyCall
using DSP
using SparseArrays
using Base.Iterators
using Statistics

include("useful-qutrit-stuff.jl")

@pyimport seaborn as sns

sns.set_style("whitegrid")
@pyimport matplotlib.colors as mplc #for LogNorm
PyDict(pyimport("matplotlib")["rcParams"])["xtick.labelsize"] = 20
PyDict(pyimport("matplotlib")["rcParams"])["ytick.labelsize"] = 20

@pyimport matplotlib.colors as mpl_colors
@pyimport mpl_toolkits.axes_grid1 as tk

plt[:rc]("font", family="serif", size=20)
plt[:rc]("text", usetex=true)

symrand(N) = 2*rand(N) .- 1
color(cmap, x, xs) = cmap(0.25 + 0.75*(x - minimum(xs))/(maximum(xs) - minimum(xs)))
color(cmap, x, xs, α) = cmap(α + (1 - α)*(x - minimum(xs))/(maximum(xs) - minimum(xs)))
lg(x) = log(x)/log(2)


# returns Array{T,1}
# this is arguably inconsistent with broader julia convention
# (which I hate)

function binandaverage(A :: Array{T,1}, binsize :: Int) where T
    N = length(A)
    @show N, binsize
    if(N % binsize == 0)
        binned = mean(reshape(A, binsize, Int(N/binsize)), dims=1)[1,:]
    else
        numbins = (N/binsize + 1) |> floor |> Int 
        @warn "binandaverage: last bin underfilled: size $binsize, only $(N%binsize) elements left"
        binned = zeros(T, numbins)
        binned[1:(numbins-1)] = mean(reshape(A[1:(numbins - 1)*binsize], binsize, numbins-1), dims=1)[1,:]
        @show length(A[binsize*(numbins-1)+1:end])
        @assert(length(A[binsize*(numbins-1)+1:end]) < binsize)
        @show binsize*(numbins - 1)
        binned[end]   = mean(A[binsize*(numbins-1)+1:end])
    end
   return binned
end

    
#take N samples with replacement from set
cdw_resample(set :: Array{T,1}, N :: Int) where T = set[rand(1:size(set)[1], N)]
cdw_resample(set :: Array{T,1}) where T    = cdw_resample(set, size(set)[1])

# bootstrap estimate of standard deviation of mean of set
# if this is slow, might try making a some kind of lazy iterator
# to pass to std, as opposed to creating a whole vector
bootstrap(set :: Array{T,1}, N_resample :: Int) where T =  boostrap(set, N_resample, mean)
bootstrap(set :: Array{T,1}, N_resample :: Int, f :: Function) where T =  [f(cdw_resample(set)) for j = 1:N_resample] |> std

#take N samples with replacement from set
cdw_resample(set :: Array{T,1}, N :: Int) where T = set[rand(1:size(set)[1], N)]
cdw_resample(set :: Array{T,1}) where T    = cdw_resample(set, size(set)[1])

# bootstrap estimate of standard deviation of mean of set
# if this is slow, might try making a some kind of lazy iterator
# to pass to std, as opposed to creating a whole vector
bootstrap(set :: Array{T,1}, N_resample :: Int) where T =  boostrap(set, N_resample, mean)
bootstrap(set :: Array{T,1}, N_resample :: Int, f :: Function) where T =  [f(cdw_resample(set)) for j = 1:N_resample] |> std


Σ = sum

unzip(A :: Array{Tuple{T,S}} where {T,S}) = ([a[1] for a in A], [a[2] for a in A])
embed(a, Id, L) = [reduce(kron, cat([Id for i = 1:(j-1)], [a], [Id for i = j+1:L], dims=1)) for j in 1:L]



git_commit() = String(read(pipeline(`git log`, `head -1`, `cut -d ' ' -f 2`, `cut -b 1-7`))[1:end-1])
git_commit(path :: String) = cd(git_commit, path)


function stamp(loc, d)
    str = reduce((*), ["$k $v\n" for (k,v) in d])
    str = str[1:end-1] #pyplot doesn't like the trailing newline
    text(loc..., str, fontsize=10, color="grey")
end

arr1d(a :: Array) = reshape(a, length(a))

import Base.apply
(t :: Tuple{<:Function,<:Function})(arg) = (t[1](arg), t[2](arg))
rand(10) |> (minimum, maximum)


int_lgstr(x :: Number) = "2^{$(x |> lg |> Int)}"

function query(df :: DataFrame, qs)
    inds = ones(Bool, size(df,1))
    for (k,v) in qs
        inds = inds .& (df[!,k] .== v)
    end
    return df[inds,:]
end

######################################################################
# read the postprocessed MPS data
itensorsjl_commit = "b7aa90c"
script_commit     = "03eb2b8"
subdate           = "2020-02-21"
jobname           = "M03"

itensors_dir = ENV["ITENSORSJL_DIR"]
nb_itensorsjl_commit = git_commit(itensors_dir)

metadata = Dict(["nb"     => nb,
          "script" => script_commit,
          "gs ITensors.jl" => itensorsjl_commit,
          "nb ITensors.jl" => nb_itensorsjl_commit,
          "subdate"        => subdate,
    ])

θmin = 0.05
θmax = 1.95
dθ   = 0.05


χ0s = [1]

ls = 3:7

χ0 = 1
df = DataFrame()
mn_df = DataFrame()

for L in [8,16,32,64,128]
    for λ in [2.0^-j for j in 1:13]
        dir = "$datadir/$jobname/$subdate/$(itensorsjl_commit)-$(script_commit)_L$L-thetamin$θmin-dtheta$dθ-thetamax$θmax-lambda$λ-chi01/" 
        new_df, new_mn_df = deserialize("$dir/postprocessed.p")
        new_df[!,:L] .= L
        new_df[!,:λ] .= λ
        new_mn_df[!,:L] .= L
        new_mn_df[!,:λ] .= λ
        global df = vcat(df, new_df)
        global mn_df = vcat(mn_df, new_mn_df)
    end
end


######################################################################
# two-point


L = tL = 128
tdf = query(df, [(:λ, 2.0^-13)
                 (:L, L)])
tdf = tdf[0.8 * π/4 .<= tdf[!,:θ] .<= 1.2 * π/4, :]

θs = sort(tdf[!, :θ])
δθ = θs[2] - θs[1]

jl = L/4 |> Int
jrs = (L/4 + 1) : L
cmap = get_cmap("viridis")
function label(θ)
    if θ ≈ π/4
        return L"\theta = \pi/4"
    elseif (abs(θ - π/4) <= 2*δθ) || (θ == minimum(θs))   || (θ == maximum(θs))
        return "\$\\theta = $(θ/(π/4))\\ \\pi/4\$"
    end
end

color(θ) = if θ == π/4 "black" else color(cmap, θ, θs) end
for rw in eachrow(tdf)
   plot(jrs .- jl, rw[:stpmn]/2, ".-", color=color(rw[:θ]), label=label(rw[:θ]))
end
title("\$L = $L\$")
δx = 1:L/2

m0 = 0.17
A = 1; β = 0.044
plot(δx, A * δx.^(-β) .+ (m0 - A) , ":", label="\$$A\\; \\delta x^{-$β} - $(A - m0)\$", color="red")


A = 10; β = 0.004
plot(δx, A * δx.^(-β) .+ (m0 - A) , "--", label="\$$A\\; \\delta x^{-$β} - $(A - m0)\$", color="red")

legend(loc = "upper left", bbox_to_anchor=(1.0,1.0))
ylabel("two-point mana density \$m(\rho_{ij})\$")
xlabel("\$\\delta x = j - i\$")
semilogx()
ylim(0, 0.2)
fn = "$figdir/$(nb)_twopoint-mana-L$L-semilogx.pdf"
@show fn
flush(stdout)
savefig(fn, bbox_inches="tight")
clf()


######################################################################
# do the exact (Krylov)

L = krylov_L
Zv = embed(Z, I3, L)
Xv = embed(X, I3, L)

field = sum(X + X' for X in Xv)
bond = sum(Zv[j]*Zv[j+1]' for j in 1:(L-1))
bond += bond'

θs = (0:0.01:2) * π/4
#θs = (0:0.2:2) * π/4
Nθ = length(θs)
kdf = DataFrame( [:θ => θs,
                 :nconv => zeros(Nθ),
                 :niter => zeros(Nθ),
                 :Z     => zeros(Complex{Float64},Nθ),
                 :X     => zeros(Complex{Float64},Nθ),
                 :mn    => zeros(Float64,Nθ),
                ])

@showprogress for (jθ, θ) in enumerate(θs)
    H = -cos(θ)*field - sin(θ)*bond

    # when there is no ground state degeneracy, we don't need to worry
    # about where the Krylov starts. (The gap is ~ cos(θ)^L which is
    # not so small, for these $L$, that the method won't find it.)
    #
    # But at θ = π/2, there *is* a (threefold) ground state
    # degeneracy, and we want to pick a reasonable element of it.
    v0 = zeros(Complex{Float64}, 3^L)
    v0[1] = 1
    d, v, nconv, niter = eigs(H, v0 = v0)
    kdf[jθ, :nconv] = nconv
    kdf[jθ, :niter] = niter
    gs = v[:,1]
    kdf[jθ, :Z]     = mean(gs' * Zv[j] * gs for j in 1:L)
    kdf[jθ, :X]     = mean(gs' * Xv[j] * gs for j in 1:L)
    
    ρ = reshape(gs ⊗ gs', ([3 for j in 1:2*L]...))
    kdf[jθ, :mn]    = mana(ρ)
end

######################################################################
# plot

L = 128

λ = 2.0^-10
tdf = query(mn_df, [(:L, L)
                    (:λ, λ)])
cmap = get_cmap("OrRd")
ls = 1:7 
for l in ls
    plot(tdf[!,:θ], tdf[!,Symbol("smn$(l)")]/l, ".-", color=color(cmap, l, ls), label="\$l = $l\$")
end

plot(θs, kdf[!,:mn]/krylov_L, "-", color="black", label="\$N = $(krylov_L)\$")



legend(loc="upper left", bbox_to_anchor=(1.0,1.0))
title("\$L = $L, \\lambda = $(λ |> int_lgstr)\$")
ylabel(L"mana density $m$")
xlabel(L"\theta")
axvline(π/4, linestyle=":", color="gray")

fn = "$figdir/$(nb)_mana-density-cat_L$(L).pdf"
@show fn
flush(stdout)
savefig(fn, bbox_inches="tight")