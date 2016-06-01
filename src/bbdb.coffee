bbdb = exports

#Represents a connection to the database that powers bubble bot
bbdb.BBDatabase = class BBDatabase extends databases.Postgres
    #given a type, returns an array of all the ids of that type
    list_objects: (type) ->

    #Given an object, returns the property with the given name
    get_property: (type, id, name) ->

    #Given an object, returns all the properties for that object.
    get_properties: (type, id) ->

    #Given an object, sets the property with the given name
    set_property: (type, id, name, value) ->
        #see jsonb_set here: https://www.postgresql.org/docs/9.5/static/functions-json.html

    #Creates a new object, optionally with the given parent and initial properties
    create_object: (type, id, parent_type, parent_id, initial_properties) ->

    #Deletes this object from the database
    delete_object: (type, id) ->

    #Returns true if an object with this type and id exists
    exists: (type, id) ->

    #Returns the immediate parent, or if parent_type is set, searches upwards til it
    #finds an ancestor of that type.
    #
    #Returns [parent_type, parent_id], or [null, null] if not found
    find_parent: (type, id, parent_type) ->

    #Lists all immediate children.  If child_type is set, filters by child type
    #
    #Returns [[child_type, child_id], [child_type, child_id]...]
    children: (type, id, child_type) ->

    #Creates an entry in the history table
    add_history: (history_type, history_id, reference, properties) ->

    #Returns the last n_entries from the given history
    recent_history: (history_type, history_id, n_entries) ->

    #Finds entries for the given parameters
    find_entries: (history_type, history_id, reference) ->

    #Deletes entries for the given parameters
    delete_entries: (history_type, history_id, reference) ->


    #Scheduler support

    #Sets the given task to run at the given timestamp with the given properties
    schedule_task: (timestamp, task, properties) ->

    #If there is a task with the same name already in the scheduler, update the properties.
    #Otherwise, insert a new task scheduled to run now.
    upsert_task: (task, properties) ->

    #Retrieves the first task that a) is unclaimed and b) is ready to go.
    #
    #Marks the retrieved task as claimed.
    #
    #owner_id represents who we want to say is claiming the task.  Should pass in null
    #if unknown, and a new one will be generated.
    #
    #Return {owner_id, task_data}.  Task_data will be null if there is nothing
    get_next_task: (owner_id) ->

    #Indicates that we finished a task and can remove it from the scheduler
    complete_task: (id) ->

    #Indicate that for some reason we could not complete the task, so we need to release it
    release_task: (id) ->



bbobjects = require './bbobjects'
databases = require './databases'


#We add some templates for creating the service
templates = require './templates'

templates.BBDBService = class BBDBService extends templates.RDSService
    #We override the logic for fetching the actual instance, since we can't
    #rely on BBDB to find BBDB
    rds_instance: (instance) -> bbobjects.get_bbdb_instance()

    #We need to store our credentials in s3 instead of in the bubblebot database,
    #since we are the bubblebot database!
    use_s3_credentials: -> true

    rds_options: -> {
        Engine: 'postgres'
        EngineVersion: '9.5.2'
    }

    #BBDB doesn't have to be terribly fast or robust, but should not be publicly
    #accessible, and should have good backups
    get_sizing: -> {
        AllocatedStorage: 5
        DBInstanceClass: 'db.t2.micro'
        BackupRetentionPeriod: 30
        MultiAZ: false
        StorageType: 'standard'
        PubliclyAccessible: false
    }

    get_additional_tests: -> []

    get_migrations: -> [
        "
        CREATE TABLE bbobjects (
            type varchar(512),
            id varchar(512),
            parent_id varchar(512),
            parent_type varchar(512),
            properties jsonb,
            PRIMARY KEY (type, id)
        );
        CREATE INDEX ON bbobjects (parent_id, parent_type);

        CREATE TABLE history (
            history_type varchar(512),
            history_id varchar(512),
            timestamp bigint,
            reference varchar(512),
            properties jsonb
        );
        CREATE INDEX ON history (history_type, history_id, timestamp);
        CREATE INDEX ON history (history_type, history_id, reference);

        CREATE TABLE scheduler (
            id bigserial,            --uid of task instance
            timestamp bigint,        --when we should run it
            owner bigint,            --who claimed the task
            task varchar(512),       --name of the task
            properties jsonb,        --data to pass to the task
            PRIMARY KEY (id)
        );
        CREATE INDEX ON scheduler (timestamp);
        CREATE INDEX ON scheduler (task);

        CREATE TABLE scheduler_owners (
            owner_id bigserial,
            last_access bigint,
            PRIMARY KEY (owner_id)
        )
        "
    ]


    get_rollbacks: -> [
        "
        DROP TABLE bbobjects, history, scheduler, scheduler_owners;
        "
    ]
