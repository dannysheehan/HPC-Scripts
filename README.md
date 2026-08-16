# HPC-Scripts

Unix admin scripts from **Barrine**, the University of Queensland Research Computing Centre HPC cluster (2010–2016). Three of them still fill a real niche. The rest is Barrine glue.

Changes go on a branch and land on `main` through a pull request.

## Barrine

Barrine was UQ's campus HPC at St Lucia. RCC named clusters after Queensland lakes (Barrine, Tinaroo, Awoonga, Euramoo, Eacham). It was [installed in 2010](https://coo.uq.edu.au/operational-areas/information-technology-services/about-its/history-of-computing).

By 2013 it had 384 compute nodes and just over 3,000 cores on InfiniBand, a 92 TB [Panasas](https://en.wikipedia.org/wiki/Panasas) parallel filesystem, HSM archive with remote mirroring, and PBS Professional. RCC ran it. It hosted Bioinformatics Resource Australia EMBL web services and an EBI FTP mirror, and was used by groups across Australia, especially bioinformatics, physics, and mechanical engineering. ([RCC newsletter, August 2013](https://rcc.uq.edu.au/files/1790/newsletter-201308.pdf))

In April 2016 RCC [replaced it with Tinaroo](https://rcc.uq.edu.au/article/2022/06/new-uq-hpc-system-replace-barrine-month), an SGI Rackable system at the Polaris Data Centre in Springfield: about 80% more cores, 4× average memory, 8× peak performance, on upgraded GPFS rather than Panasas. Tinaroo, FlashLite, Awoonga, and Wiener have since been retired in favour of [Bunya](https://rcc.uq.edu.au/systems/high-performance-computing).

These scripts are from that Barrine stack: Panasas quotas, DMF-style HSM staging, PBS/Torque login-node watches, scratch expiry.

## Still useful

### expirefiles.py

Scratch expiry is still universal. Centres still warn-then-delete on atime/mtime: [TACC](https://docs.tacc.utexas.edu/include/scratchpolicy/) purges scratch after 10 days; [SMU](https://southernmethodistuniversity.github.io/hpc_docs/policies/scratch.html) is rolling a 60-day purge in 2026. `expirefiles.py` is that policy as a script, for a site without Robinhood or Spectrum Scale ILM. Same problem, 2015 Python 2.

Details: [expirefiles.md](cleanup/expirefiles.md)

### chunkybackup.sh

Small files on tape is still a real pain. Newer HSM (Versity) packs for you; some sites still tell users to tar into chunks. `chunkybackup.sh` is the user-run version of that, with restart-from-chunk, which is the part that is actually clever. Must be run as the data owner, not root.

Details: [chunkybackup.md](hsm/chunkybackup.md)

### goodcitizen.sh

Login-node abuse is eternal. `goodcitizen.sh` is the old email-the-offender approach. Today that is cgroups and systemd slices. The `watch qstat` check is Torque-specific and dated.

Details: [goodcitizen.md](scheduler/goodcitizen.md)

## Barrine glue

The rest only made sense on that machine.

The Panasas set ([apan_du.sh](storage/apan_du.sh), [apan_du_notify.sh](storage/apan_du_notify.sh), [lsdircount.sh](storage/lsdircount.sh), [aquota.sh](storage/aquota.sh)) only matters if you still have Panasas. [dpart.sh](hsm/dpart.sh) / [hsync.sh](hsm/hsync.sh) only matter if you still stage files off DMF-style HSM. [rquota](storage/rquota) is a 40-line prettifier for GPFS `mmlsquota`. [pbsqcheck.sh](scheduler/pbsqcheck.sh) is Torque/PBS.

[cleantmp.sh](cleanup/cleantmp.sh), [volfillrate.sh](storage/volfillrate.sh), [user-disk-usage.sh](storage/user-disk-usage.sh), [usage-check.sh](scheduler/usage-check.sh), and [dynamic-motd.sh](scheduler/dynamic-motd.sh) are one-liners every distro or monitoring stack already covers.

If this repo is meant to be useful to anyone else, the keepers are the ideas in expirefiles and chunkybackup. Everything else is site history.

## Layout

| Directory | What |
| --- | --- |
| [cleanup/](cleanup/) | Scratch expiry (`expirefiles.py`) and `/tmp` cleanup |
| [hsm/](hsm/) | Tape packing (`chunkybackup.sh`) and DMF-style staging |
| [scheduler/](scheduler/) | Login-node watch and PBS/Torque helpers |
| [storage/](storage/) | Panasas, GPFS quota, disk usage |
