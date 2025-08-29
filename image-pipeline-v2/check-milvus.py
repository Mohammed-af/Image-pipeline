from pymilvus import connections, Collection, utility

# Connect to Milvus
connections.connect(host="localhost", port=19530)

# Check collections
print("\n=== MILVUS COLLECTIONS ===")
collections = utility.list_collections()
print(f"Available collections: {collections}")

for coll_name in collections:
    coll = Collection(coll_name)
    print(f"\n{coll_name}:")
    print(f"  Vectors stored: {coll.num_entities}")
    
print("\n========================")
