import json
import logging
import os
import time
from typing import List, Optional

import motor.motor_asyncio
from bson import ObjectId
from fastapi import Body, FastAPI, HTTPException, status
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from fastapi_cache.decorator import cache
from logmiddleware import RouterLoggingMiddleware, logging_config
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from pydantic.functional_validators import BeforeValidator
from pymongo import errors
from redis import asyncio as aioredis
from typing_extensions import Annotated

# Configure JSON logging
logging.config.dictConfig(logging_config)
logger = logging.getLogger(__name__)

app = FastAPI()
app.add_middleware(
    RouterLoggingMiddleware,
    logger=logger,
)

DATABASE_URL = os.environ["MONGODB_URL"]
DATABASE_NAME = os.environ["MONGODB_DATABASE_NAME"]
REDIS_URL = os.getenv("REDIS_URL", None)


def nocache(*args, **kwargs):
    def decorator(func):
        return func

    return decorator


if REDIS_URL:
    logger.info("[INIT] Используется декоратор cache из fastapi_cache")
    cache = cache
else:
    logger.warning("[INIT] REDIS_URL не установлен, используется nocache")
    cache = nocache


client = motor.motor_asyncio.AsyncIOMotorClient(DATABASE_URL)
db = client[DATABASE_NAME]

# Represents an ObjectId field in the database.
# It will be represented as a `str` on the model so that it can be serialized to JSON.
PyObjectId = Annotated[str, BeforeValidator(str)]


@app.on_event("startup")
async def startup():
    logger.info(f"[STARTUP] REDIS_URL: {REDIS_URL}")
    if REDIS_URL:
        try:
            logger.info("[STARTUP] Подключение к Redis...")
            redis = aioredis.from_url(REDIS_URL, encoding="utf8", decode_responses=True)
            # Проверяем подключение
            await redis.ping()
            logger.info("[STARTUP] ✅ Redis подключен успешно")
            FastAPICache.init(RedisBackend(redis), prefix="api:cache")
            logger.info("[STARTUP] ✅ FastAPICache инициализирован")
            cache_status = FastAPICache.get_enable()
            logger.info(f"[STARTUP] Cache enabled: {cache_status}")
        except Exception as e:
            logger.error(f"[STARTUP] ❌ Ошибка подключения к Redis: {e}", exc_info=True)
    else:
        logger.warning("[STARTUP] REDIS_URL не установлен, кэш отключен")


class UserModel(BaseModel):
    """
    Container for a single user record.
    """

    id: Optional[PyObjectId] = Field(alias="_id", default=None)
    age: int = Field(...)
    name: str = Field(...)


class UserCollection(BaseModel):
    """
    A container holding a list of `UserModel` instances.
    """

    users: List[UserModel]


@app.get("/")
@cache(expire=60)
async def root():
    logger.info("[ROOT] 🔄 Функция root() ВЫЗВАНА - выполняется запрос к БД")
    start_time = time.time()
    collection_names = await db.list_collection_names()
    collections = {}
    for collection_name in collection_names:
        collection = db.get_collection(collection_name)
        collections[collection_name] = {
            "documents_count": await collection.count_documents({})
        }
    try:
        replica_status = await client.admin.command("replSetGetStatus")
        replica_status = json.dumps(replica_status, indent=2, default=str)
    except errors.OperationFailure:
        replica_status = "No Replicas"

    topology_description = client.topology_description
    read_preference = client.client_options.read_preference
    topology_type = topology_description.topology_type_name
    replicaset_name = topology_description.replica_set_name

    shards = None
    if topology_type == "Sharded":
        shards_list = await client.admin.command("listShards")
        shards = {}
        for shard in shards_list.get("shards", {}):
            shards[shard["_id"]] = shard["host"]

    cache_enabled = False
    if REDIS_URL:
        cache_enabled = FastAPICache.get_enable()

    elapsed = time.time() - start_time
    logger.info(f"[ROOT] ✅ Функция root() завершена за {elapsed:.3f}s")
    
    return {
        "mongo_topology_type": topology_type,
        "mongo_replicaset_name": replicaset_name,
        "mongo_db": DATABASE_NAME,
        "read_preference": str(read_preference),
        "mongo_nodes": client.nodes,
        "mongo_primary_host": client.primary,
        "mongo_secondary_hosts": client.secondaries,
        "mongo_is_primary": client.is_primary,
        "mongo_is_mongos": client.is_mongos,
        "collections": collections,
        "shards": shards,
        "cache_enabled": cache_enabled,
        "status": "OK",
    }


@app.get("/{collection_name}/count")
@cache(expire=60)
async def collection_count(collection_name: str):
    logger.info(f"[COUNT] 🔄 Функция collection_count('{collection_name}') ВЫЗВАНА - выполняется запрос к БД")
    start_time = time.time()
    collection = db.get_collection(collection_name)
    items_count = await collection.count_documents({})
    elapsed = time.time() - start_time
    logger.info(f"[COUNT] ✅ Функция collection_count('{collection_name}') завершена за {elapsed:.3f}s, count={items_count}")
    # status = await client.admin.command('replSetGetStatus')
    # import ipdb; ipdb.set_trace()
    return {"status": "OK", "mongo_db": DATABASE_NAME, "items_count": items_count}


@app.get(
    "/{collection_name}/users",
    response_description="List all users",
    response_model=UserCollection,
    response_model_by_alias=False,
)
@cache(expire=60)
async def list_users(collection_name: str):
    """
    List all of the user data in the database.
    The response is unpaginated and limited to 1000 results.
    """
    logger.info(f"[LIST_USERS] 🔄 Функция list_users('{collection_name}') ВЫЗВАНА - выполняется запрос к БД")
    start_time = time.time()
    time.sleep(1)
    collection = db.get_collection(collection_name)
    users = await collection.find().to_list(1000)
    elapsed = time.time() - start_time
    logger.info(f"[LIST_USERS] ✅ Функция list_users('{collection_name}') завершена за {elapsed:.3f}s, users_count={len(users)}")
    return UserCollection(users=users)


@app.get(
    "/{collection_name}/users/{name}",
    response_description="Get a single user",
    response_model=UserModel,
    response_model_by_alias=False,
)
async def show_user(collection_name: str, name: str):
    """
    Get the record for a specific user, looked up by `name`.
    """

    collection = db.get_collection(collection_name)
    if (user := await collection.find_one({"name": name})) is not None:
        return user

    raise HTTPException(status_code=404, detail=f"User {name} not found")


@app.post(
    "/{collection_name}/users",
    response_description="Add new user",
    response_model=UserModel,
    status_code=status.HTTP_201_CREATED,
    response_model_by_alias=False,
)
async def create_user(collection_name: str, user: UserModel = Body(...)):
    """
    Insert a new user record.

    A unique `id` will be created and provided in the response.
    """
    collection = db.get_collection(collection_name)
    new_user = await collection.insert_one(
        user.model_dump(by_alias=True, exclude=["id"])
    )
    created_user = await collection.find_one({"_id": new_user.inserted_id})
    return created_user
