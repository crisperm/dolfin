// Copyright (C) 2012 Chris N. Richardson
//
// This file is part of DOLFIN.
//
// DOLFIN is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// DOLFIN is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with DOLFIN. If not, see <http://www.gnu.org/licenses/>.
//
// Modified by Garth N. Wells, 2012
//
// First added:  2012-05-22
// Last changed: 2012-10-01

#ifndef __DOLFIN_HDF5FILE_H
#define __DOLFIN_HDF5FILE_H

#ifdef HAS_HDF5

#include <string>
#include <utility>
#include <vector>
#include "dolfin/common/types.h"
#include "GenericFile.h"
#include "HDF5Interface.h"

namespace dolfin
{

  class Function;
  class GenericVector;
  class Mesh;

  class HDF5File : public GenericFile
  {
  public:

    /// Constructor
    HDF5File(const std::string filename, const bool use_mpiio=true);

    /// Destructor
    ~HDF5File();

    /// Write vector to file in HDF5 folder 'Vector'. Multiple calls
    /// will save in the same file with incrementing dataset names
    void operator<< (const GenericVector& x);

    /// Read vector from file (in HDF5 folder 'Vector' for dataset 0)
    void operator>> (GenericVector& x);

    /// Read vector from HDF5 file
    void read(const std::string dataset_name, GenericVector& x,
              const bool use_partition_from_file=true);

    /// Write Mesh to file (using true topology indices)
    void operator<< (const Mesh& mesh);

    /// Write Mesh to file. 'true_topology_indices' indicates
    /// whether the true global vertex indices should be used when saving

    /// With true_topology_indices=true
    /// ===============================
    /// Vertex coordinates are reordered into global order before saving
    /// Topological connectivity uses global indices
    /// * may exhibit poor scaling due to MPI distribute of vertex
    /// coordinates
    /// * can be read back in by any number of processes

    /// With true_topology_indices=false
    /// ================================
    /// Vertex coordinates are in local order, with an offset
    /// Topological connectivity uses the local + offset values for indexing
    /// * some duplication of vertices => larger file size
    /// * reduced MPI communication when saving
    /// * more difficult to read back in, especially if nprocs > than
    ///   when writing
    /// * efficient to read back in if nprocs is the same, and
    ///   partitioning is the same
    void write_mesh(const Mesh& mesh);

    void write_mesh(const Mesh& mesh, const uint cell_dim);

    /// Read Mesh from file
    void operator>> (Mesh& mesh);

    /// Check is dataset with given name exists in HDF5 file
    bool dataset_exists(const std::string dataset_name) const;

  private:

    // Friend
    friend class XDMFFile;

    // Open HDF5 file
    void open_hdf5_file(bool truncate);

    // Write contiguous data to HDF5 data set. Data is flattened into
    // a 1D array, e.g. [x0, y0, z0, x1, y1, z1] for a vector in 3D
    template <typename T>
    void write_data(const std::string group_name,
                    const std::string dataset_name,
                    const std::vector<T>& data,
                    const std::vector<uint> global_size);

    // Search dataset names for one beginning with search_term
    std::string search_list(const std::vector<std::string>& list,
                            const std::string& search_term) const;

    // Generate HDF5 dataset names for mesh topology and coordinates
    std::string mesh_coords_dataset_name(const Mesh& mesh) const;
    std::string mesh_index_dataset_name(const Mesh& mesh) const;
    std::string mesh_topology_dataset_name(const Mesh& mesh) const;

    // Reorganise data into global order as defined by global_index
    // global_index contains the global index positions
    // local_vector contains the items to be redistributed
    // global_vector is the result: the local part of the new global vector created.
    template <typename T>
    void redistribute_by_global_index(const std::vector<uint>& global_index,
                                      const std::vector<T>& local_vector,
                                      std::vector<T>& global_vector);


    // HDF5 file descriptor/handle
    bool hdf5_file_open;
    hid_t hdf5_file_id;

    // Parallel mode
    const bool mpi_io;

  };

  //---------------------------------------------------------------------------
  template <typename T>
  void HDF5File::write_data(const std::string group_name,
                            const std::string dataset_name,
                            const std::vector<T>& data,
                            const std::vector<uint> global_size)
  {
    dolfin_assert(hdf5_file_open);

    //FIXME: Get groups from dataset_name and recursively create groups

    // Check that group exists and create is required
    if (!HDF5Interface::has_group(hdf5_file_id, group_name))
      HDF5Interface::add_group(hdf5_file_id, group_name);

    /*
    if (global_size.size() > 2)
    {
      dolfin_error("HDF5File.h",
                   "write data set to HDF5 file",
                   "Writing data of rank > 2 is not yet supported. It will be fixed soon");
    }
    */

    dolfin_assert(global_size.size() > 0);

    // Get number of 'items'
    uint num_local_items = 1;
    for (uint i = 1; i < global_size.size(); ++i)
      num_local_items *= global_size[i];
    num_local_items = data.size()/num_local_items;

    // Compute offet
    const uint offset = MPI::global_offset(num_local_items, true);
    std::pair<uint, uint> range(offset, offset + num_local_items);

    // Write data to HDF5 file
    HDF5Interface::write_dataset(hdf5_file_id, dataset_name, data,
                                 range, global_size, mpi_io, false);
  }
  //---------------------------------------------------------------------------


}
#endif
#endif