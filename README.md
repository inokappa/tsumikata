# tsumikata

## これは

ECS のサービスについて, 以下の操作を提供します.

* タスクの希望する起動数の変更
* クラスタ内の全サービスの停止, AutoScaling のキャパシティ変更

## 必要なもの

* Docker
* docker-compose
* AWS IAM User (それなりの権限が必要です)

## 使い方

### Build

はじめにコンテナをビルドします.

```sh
docker-compose build
```

### サービス一覧

```sh
docker-compose run --rm list --cluster=${YOUR_ECS_CLUSTER}
```

以下, 実行例.

```sh
$ docker-compose run --rm list --cluster=oreno-fargate-cluster
+---------+--------------------+---------+---------+--------+--------+
| Name    | Task               | Desired | Running | Status | MinCap |
+---------+--------------------+---------+---------+--------+--------+
| sample2 | oreno-task-def:6   | 2       | 0       | ACTIVE |        |
| sample1 | oreno-task-def:6   | 1       | 0       | ACTIVE | 1      |
| sample3 | oreno-task-def:6   | 2       | 0       | ACTIVE |        |
+---------+--------------------+---------+---------+--------+--------+
```

### サービス一覧 (JSON フォーマット)

```sh
docker-compose run --rm list --cluster=${YOUR_ECS_CLUSTER} --json
```

以下, 実行例.

```sh
$ docker-compose run --rm list --cluster=oreno-fargate-cluster --json
[
  {
    "Name": "sample2",
    "Task": "oreno-task-def:6",
    "Desired": 2,
    "Running": 0,
    "Status": "ACTIVE",
    "MinCap": ""
  },
  {
    "Name": "sample1",
    "Task": "oreno-task-def:6",
    "Desired": 1,
    "Running": 0,
    "Status": "ACTIVE",
    "MinCap": 1
  },
  {
    "Name": "sample3",
    "Task": "oreno-task-def:6",
    "Desired": 2,
    "Running": 0,
    "Status": "ACTIVE",
    "MinCap": ""
  }
]
```

この JSON ファイルをファイルに保存しておくことで, 後述の「クラスタ内の全てのサービスを起動」で利用します.

```sh
$ docker-compose run --rm list --cluster=oreno-fargate-cluster --json | tee -a oreno-fargate-cluster.json
[
  {
    "Name": "sample2",
    "Task": "oreno-task-def:6",
    "Desired": 2,
    "Running": 0,
    "Status": "ACTIVE",
    "MinCap": ""
  },
  {
    "Name": "sample1",
    "Task": "oreno-task-def:6",
    "Desired": 1,
    "Running": 0,
    "Status": "ACTIVE",
    "MinCap": 1
  },
  {
    "Name": "sample3",
    "Task": "oreno-task-def:6",
    "Desired": 2,
    "Running": 0,
    "Status": "ACTIVE",
    "MinCap": ""
  }
]
```

### クラスタ内の全てのサービスを停止

```sh
docker-compose run --rm down --cluster=${YOUR_ECS_CLUSTER}
```

以下, 実行例.

```sh
$ docker-compose run --rm down --cluster=oreno-fargate-cluster
Change desired size of tasks in sample2 to 0.
Changed.
Change desired size of tasks in sample1 to 0.
Changed.
Change desired size of tasks in sample3 to 0.
Changed.
Change capacity size of service/oreno-fargate-cluster/sample1 to 0.
Changed.
```

### クラスタ内の全てのサービスを起動

```sh
docker-compose run --rm up --cluster=${YOUR_ECS_CLUSTER} --file=${JSON_FILE_NAME}
```

以下, 実行例.

```sh
$ docker-compose run --rm up --cluster=oreno-fargate-cluster --file=oreno-fargate-cluster.json
Change desired size of tasks in sample2 to 2.
Changed.
Change capacity size of service/oreno-fargate-cluster/sample1 to 1.
Changed.
Change desired size of tasks in sample1 to 1.
Changed.
Change desired size of tasks in sample3 to 2.
Changed.
```

### クラスタ内の指定したサービスタスクの希望する起動数を変更

```sh
docker-compose run --rm change --cluster=${YOUR_ECS_CLUSTER} --service=${SERVICE_NAME} --size=${SIZE}
```

以下, 実行例.

```shell
$ docker-compose run --rm change --cluster=oreno-fargate-cluster --service=sample1 --size=1
Change desired size of tasks in sample1 to 1.
Changed.
$ docker-compose run --rm list --cluster=oreno-fargate-cluster
+---------+--------------------+---------+---------+--------+--------+
| Name    | Task               | Desired | Running | Status | MinCap |
+---------+--------------------+---------+---------+--------+--------+
| sample2 | oreno-task-def:6   | 0       | 0       | ACTIVE |        |
| sample1 | oreno-task-def:6   | 1       | 0       | ACTIVE | 0      |
| sample3 | oreno-task-def:6   | 0       | 0       | ACTIVE |        |
+---------+--------------------+---------+---------+--------+--------+
```
